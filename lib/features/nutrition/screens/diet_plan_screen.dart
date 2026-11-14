import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:icanbefitter/core/constants/diet_strategies.dart';
import 'package:icanbefitter/core/constants/food_types.dart';
import 'package:icanbefitter/core/services/error_telemetry.dart';
import 'package:icanbefitter/core/services/sync_service.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/shared/repositories/food_repository.dart';
import 'package:icanbefitter/features/profile/providers/profile_provider.dart';
import 'package:icanbefitter/shared/repositories/user_repository.dart';
import 'package:icanbefitter/shared/widgets/food_type_chips.dart';
import '../providers/nutrition_provider.dart';
import '../providers/diet_plan_provider.dart';
import '../services/curated_diet_plan_generator.dart';
import '../services/diet_plan_flags.dart';
import '../services/diet_plan_generator.dart';
import '../services/diet_plan_pdf.dart';
import '../services/diet_plan_swap.dart';
import '../services/diet_strategy_flags.dart';
import '../widgets/diet_strategy_section.dart';

part 'diet_plan_screen_models.dart';

// Diet plan Unit 2a: the "your saved plan was for X" notice shows once per
// (saved plan id, food type) per app session.
final Set<String> _mismatchNoticeShown = <String>{};

/// Test seam: clears the once-per-session mismatch notice record.
@visibleForTesting
void debugResetDietPlanMismatchNotices() => _mismatchNoticeShown.clear();

/// Diet plan generator — FREE for everyone.
/// Generated from food database (zero API cost).
/// User can preview the plan, swap food items, save, and download as PDF (FREE).
class DietPlanScreen extends ConsumerStatefulWidget {
  const DietPlanScreen({super.key});

  @override
  ConsumerState<DietPlanScreen> createState() => _DietPlanScreenState();
}

class _DietPlanScreenState extends ConsumerState<DietPlanScreen> {
  late List<_MealPlan> _mealPlans;
  bool _saved = false;
  bool _checkedSaved = false;
  // Cached so _swapItem applies the SAME food-type rule as generation
  // (plan-review round 2, finding 5: a veg user could be offered chicken).
  // Read through the one normaliser (diet plan Unit 2a).
  FoodType _foodType = kDefaultFoodType;
  // True while a food-type change is being saved; chip taps are ignored.
  bool _changingFoodType = false;
  // Regenerate taps this session; folded into the generator seed.
  int _regenerations = 0;

  @override
  void initState() {
    super.initState();
    _mealPlans = [];
    // Defer plan generation to after build so ref.read is available.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _generatePlan();
    });
  }

  void _generatePlan() {
    // Cache diet preference for the swap filter on BOTH paths (fresh +
    // saved-plan load) — B-pass finding 3: a vegan user loading a saved
    // plan otherwise got veg-filtered (dairy-allowed) swap alternatives.
    _foodType = foodTypeOfProfile(UserRepository.instance.getProfile());

    // Check for saved plan on first entry only. Obs 8 fix: load it
    // immediately instead of gating behind a dialog — the AppBar's
    // existing Regenerate (:498) and Save (:514) icons already give
    // the user both actions without a blocking modal.
    if (!_checkedSaved) {
      _checkedSaved = true;
      final savedPlan = UserRepository.instance.getSavedDietPlan();
      if (savedPlan != null) {
        if (savedPlanMatchesFoodType(savedPlan, _foodType)) {
          _loadSavedPlan(savedPlan);
          return;
        }
        // Unit 2a: a plan saved for another food type is not shown.
        _generateFreshPlan();
        _noticeSavedPlanMismatch(savedPlan);
        return;
      }
    }

    _generateFreshPlan();
  }

  void _noticeSavedPlanMismatch(Map<String, dynamic> savedPlan) {
    final key = '${savedPlan['id']}|${_foodType.storageKey}';
    if (!_mismatchNoticeShown.add(key) || !mounted) return;
    final now = _foodType.label;
    // A plan saved before food types existed has no food_type to name.
    final first = savedPlan['food_type'] == null
        ? 'Your saved plan has foods outside $now.'
        : 'Your saved plan was for ${foodTypeOf(savedPlan['food_type']).label}.';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '$first Here is a $now plan; save to keep it.',
          style: AppTypography.body.copyWith(fontSize: 13),
        ),
        backgroundColor: AppColors.card,
      ),
    );
  }

  /// The Diet Plan screen's food-type selector: one write door
  /// (UserProfileNotifier.setFoodType), then a fresh, unsaved plan.
  Future<void> _changeFoodType(FoodType next) async {
    if (_changingFoodType || next == _foodType) return;
    setState(() => _changingFoodType = true);
    try {
      final applied =
          await ref.read(userProfileProvider.notifier).setFoodType(next);
      if (!mounted) return;
      // B-pass finding 2: a call dropped by an account change wrote nothing;
      // never announce a plan for a type that is not stored.
      if (!applied) {
        _showFoodTypeChangeFailed();
        return;
      }
      setState(() => _foodType = next);
      _generateFreshPlan();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Plan rebuilt for ${next.label}. Save to keep it.',
            style: AppTypography.body.copyWith(fontSize: 13),
          ),
          backgroundColor: AppColors.card,
        ),
      );
    } catch (e, st) {
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'diet_plan_food_type_change'));
      // The chips still show the old type (nothing changed); say so.
      if (mounted) _showFoodTypeChangeFailed();
    } finally {
      if (mounted) setState(() => _changingFoodType = false);
    }
  }

  void _showFoodTypeChangeFailed() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          "Couldn't change the food type. Try again.",
          style: AppTypography.body.copyWith(fontSize: 13),
        ),
        backgroundColor: AppColors.card,
      ),
    );
  }

  void _generateFreshPlan() {
    final targets = ref.read(macroTargetsProvider);
    final calorieTarget = targets['calories']?.round() ?? 2400;
    final proteinTarget = targets['protein']?.round() ?? 184;

    // The food type from the Hive profile, through the one normaliser
    // (diet plan Unit 2a; default Non-veg).
    final profile = UserRepository.instance.getProfile() ?? const {};
    _foodType = foodTypeOfProfile(profile);

    // Same plan all day on open; each Regenerate tap moves to the next seed
    // (before Unit 1 the tap reused the day's seed and showed the same plan).
    final seed = dietPlanSeed(DateTime.now(), _regenerations);

    // Diet plan Unit 1: the curated, catalog-only generator, unless the
    // local kill switch routes back to the legacy one (DietPlanFlags).
    final inputs = DietPlanInputs(
      calorieTarget: calorieTarget,
      proteinTarget: proteinTarget,
      dietPreference: _foodType.storageKey,
      // Same source as DailyNutritionData.fiberTarget
      // (nutrition_provider.dart:362) — no second default.
      fiberTarget: (profile['fiber_grams'] as num?)?.toInt() ?? 30,
      seed: seed,
    );
    final servicePlans = DietPlanFlags.curatedEnabled
        ? CuratedDietPlanGenerator.instance.generate(inputs)
        : DietPlanGenerator.instance.generate(inputs);

    _mealPlans = servicePlans.map(_servicePlanToScreenPlan).toList();
    if (mounted) setState(() => _saved = false);
  }

  /// Adapts the public DietMealPlan into the screen's private _MealPlan so
  /// the rest of the screen (swap UI, save UI, PDF export) keeps working.
  _MealPlan _servicePlanToScreenPlan(DietMealPlan svc) => _MealPlan(
        name: svc.name,
        slotKey: svc.slotKey,
        items: svc.items
            .map((i) => _PlanFoodItem(
                  foodId: i.foodId,
                  name: i.name,
                  servingDesc: i.servingDesc,
                  servingG: i.servingG,
                  calories: i.calories,
                  protein: i.protein,
                  carbs: i.carbs,
                  fat: i.fat,
                  category: i.category,
                  role: i.role,
                ))
            .toList(),
        targetCalories: svc.targetCalories,
        targetProtein: svc.targetProtein,
      );

  void _swapItem(int mealIndex, int itemIndex) {
    final meal = _mealPlans[mealIndex];
    final item = meal.items[itemIndex];
    // Diet plan Unit 1: catalog-only alternatives (diet_plan_swap.dart). The
    // same diet-preference rule as generation applies, UPF rows are never
    // offered, and nothing already in the plan or over its family cap is.
    final alternatives = swapAlternatives(
      foodId: item.foodId,
      category: item.category,
      calories: item.calories,
      role: item.role,
      slotKey: meal.slotKey ?? kDietMealNameToSlotKey[meal.name] ?? '',
      dietPreference: _foodType.storageKey,
      planFoodIds: [
        for (final m in _mealPlans)
          for (final i in m.items) i.foodId,
      ],
      slotOtherNames: [
        for (var j = 0; j < meal.items.length; j++)
          if (j != itemIndex) meal.items[j].name,
      ],
      repo: FoodRepository.instance,
    );

    if (alternatives.isEmpty) {
      // B-pass finding 6: silent no-op gave the tap zero feedback; the UPF +
      // diet filters narrow pools, so this is now reachable (all-UPF
      // categories).
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'No alternatives available for this item',
            style: AppTypography.body.copyWith(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary),
          ),
          backgroundColor: AppColors.card,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          duration: const Duration(seconds: 3),
        ),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(AppRadius.cardL)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.screenPadding),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.textDisabled,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Swap "${item.name}" with...',
                style: AppTypography.body.copyWith(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
              ),
              const SizedBox(height: 12),
              ...alternatives.map((alt) {
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    alt.name,
                    style: AppTypography.body.copyWith(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                  ),
                  subtitle: Text(
                    '${alt.servingDesc} \u00B7 ${alt.calories} kcal',
                    style: AppTypography.bodySm.copyWith(fontSize: 11, color: AppColors.textDim),
                  ),
                  trailing: const Icon(Icons.swap_horiz,
                      color: AppColors.accent, size: 20),
                  onTap: () {
                    setState(() {
                      _mealPlans[mealIndex].items[itemIndex] = _PlanFoodItem(
                        foodId: alt.foodId,
                        name: alt.name,
                        servingDesc: alt.servingDesc,
                        servingG: alt.servingG,
                        calories: alt.calories,
                        protein: alt.protein,
                        carbs: alt.carbs,
                        fat: alt.fat,
                        // the NEW row's category; the role is inherited
                        // (alt.role is the resolved role of the replaced item)
                        category: alt.category,
                        role: alt.role,
                      );
                    });
                    Navigator.of(ctx).pop();
                  },
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  void _savePlan() {
    final now = DateTime.now();
    final planData = {
      'id': 'diet_plan_${now.millisecondsSinceEpoch}',
      'created_at': now.toIso8601String(),
      // Unit 2a: the food type the plan was built for (a plan of another
      // type is not loaded or used for hints, savedPlanMatchesFoodType).
      'food_type': _foodType.storageKey,
      // Unit 3a: stamped only with the flag on (no reader until Unit 3b).
      if (DietStrategyFlags.enabled)
        'diet_strategy':
            dietStrategyOfTargets(ref.read(macroTargetsProvider)).storageKey,
      'meals': _mealPlans
          .map((m) => {
                'name': m.name,
                'items': m.items
                    .map((i) => {
                          'food_id': i.foodId,
                          'name': i.name,
                          'serving_desc': i.servingDesc,
                          'serving_g': i.servingG,
                          'calories': i.calories,
                          'protein': i.protein,
                          'carbs': i.carbs,
                          'fat': i.fat,
                          'category': i.category,
                        })
                    .toList(),
              })
          .toList(),
    };

    UserRepository.instance.saveDietPlan(planData);

    // Push plan to cloud so it survives reinstall (migration 048).
    unawaited(SyncService.instance.syncSavedDietPlan(planData));

    // AH.5 — refresh the nutrition screen's "From Your Diet Plan" hints
    // so a freshly-saved plan shows up on empty meal slots immediately.
    ref.invalidate(dietPlanProvider);

    setState(() => _saved = true);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Diet plan saved to your device',
          style: AppTypography.body.copyWith(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
        ),
        backgroundColor: AppColors.card,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 4),
        action: SnackBarAction(
          label: 'SHARE AS PDF',
          textColor: AppColors.accent,
          onPressed: _sharePlanAsPdf,
        ),
      ),
    );
  }

  void _loadSavedPlan(Map<String, dynamic> planData) {
    final meals = (planData['meals'] as List?) ?? [];
    _mealPlans = meals.map((m) {
      final mealMap = Map<String, dynamic>.from(m as Map);
      final items = ((mealMap['items'] as List?) ?? []).map((i) {
        final item = Map<String, dynamic>.from(i as Map);
        return _PlanFoodItem(
          foodId: item['food_id'] as String? ?? '',
          name: item['name'] as String? ?? '',
          servingDesc: item['serving_desc'] as String? ?? '',
          servingG: (item['serving_g'] as num?)?.toDouble() ?? 100,
          calories: (item['calories'] as num?)?.toInt() ?? 0,
          protein: (item['protein'] as num?)?.toInt() ?? 0,
          carbs: (item['carbs'] as num?)?.toInt() ?? 0,
          fat: (item['fat'] as num?)?.toInt() ?? 0,
          category: item['category'] as String? ?? '',
        );
      }).toList();
      final name = mealMap['name'] as String? ?? '';
      return _MealPlan(
        name: name,
        // The saved JSON stores only the meal name; the swap sheet needs the
        // slot (diet plan Unit 1).
        slotKey: kDietMealNameToSlotKey[name],
        items: items,
        targetCalories: 0,
        targetProtein: 0,
      );
    }).toList();
    if (mounted) setState(() => _saved = true);
  }

  String? _pdfStrategyLabel(Map<String, double> targets) {
    final s = dietStrategyOfTargets(targets);
    return s == DietStrategy.balanced ? null : s.label;
  }

  Future<void> _sharePlanAsPdf() async {
    if (_mealPlans.isEmpty) return;

    try {
    final targets = ref.read(macroTargetsProvider);
    final calorieTarget = targets['calories']?.round() ?? 2400;
    final proteinTarget = targets['protein']?.round() ?? 184;
    final carbTarget = targets['carbs']?.round() ?? 0;
    final fatTarget = targets['fat']?.round() ?? 0;
    final fiberTarget = (UserRepository.instance.getProfile()?['fiber_grams'] as num?)?.toInt() ?? 30;

    final Uint8List bytes = await buildDietPlanPdf(
      meals: [
        for (final meal in _mealPlans)
          (
            name: meal.name,
            items: [
              for (final item in meal.items)
                (
                  name: item.name,
                  servingDesc: item.servingDesc,
                  calories: item.calories,
                  protein: item.protein,
                  carbs: item.carbs,
                  fat: item.fat,
                ),
            ],
          ),
      ],
      foodTypeLabel: _foodType.label,
      strategyLabel: _pdfStrategyLabel(targets),
      calorieTarget: calorieTarget,
      proteinTarget: proteinTarget,
      carbTarget: carbTarget,
      fatTarget: fatTarget,
      fiberTarget: fiberTarget,
      now: DateTime.now(),
    );
    await Share.shareXFiles(
      [XFile.fromData(bytes, name: 'icanbefitter_diet_plan.pdf', mimeType: 'application/pdf')],
      subject: 'ICANBEFITTER Diet Plan',
    );
    } catch (e) {
      final errStr = e.toString();
      final clipped = errStr.length > 500 ? errStr.substring(0, 500) : errStr;
      unawaited(ErrorTelemetry.logEvent('nutrition_diet_plan_pdf_export_failed',
          message: clipped));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to generate PDF',
              style: AppTypography.bodySm),
            backgroundColor: AppColors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final targets = ref.watch(macroTargetsProvider);

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.header,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
          onPressed: () => context.go('/nutrition'),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Diet Plan',
              style: AppTypography.body.copyWith(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
            ),
            Text(
              withDietStrategyTag(
                  _foodType.shortLabel, dietStrategyOfTargets(targets)),
              key: const ValueKey('diet_plan_food_type_tag'),
              style: AppTypography.body.copyWith(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                  color: AppColors.accent),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh,
                color: AppColors.textSecondary, size: 22),
            onPressed: () {
              _regenerations++;
              _generateFreshPlan();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Plan regenerated!',
                    style: AppTypography.body.copyWith(fontSize: 13),
                  ),
                  backgroundColor: AppColors.card,
                ),
              );
            },
          ),
          IconButton(
            icon: Icon(
              _saved ? Icons.check_circle : Icons.save_outlined,
              color: _saved ? AppColors.green : AppColors.accent,
              size: 22,
            ),
            onPressed: _savePlan,
          ),
        ],
      ),
      body: _mealPlans.isEmpty
          ? const Center(
              child: CircularProgressIndicator(
                  color: AppColors.accent, strokeWidth: 2))
          : SafeArea(
              child: ListView(
                padding: const EdgeInsets.all(AppSpacing.screenPadding),
                children: [
                  _buildTdeeCard(targets),
                  const SizedBox(height: AppSpacing.sectionGap),
                  Text(
                    'Food type',
                    style: AppTypography.body.copyWith(
                        fontSize: 13, color: AppColors.textDim),
                  ),
                  const SizedBox(height: 8),
                  FoodTypeChips(
                    value: _foodType,
                    enabled: !_changingFoodType,
                    onChanged: _changeFoodType,
                  ),
                  if (DietStrategyFlags.enabled) ...[
                    const SizedBox(height: AppSpacing.sectionGap),
                    const DietStrategySection(),
                  ],
                  const SizedBox(height: AppSpacing.sectionGap),
                  _buildMacroTargets(targets),
                  const SizedBox(height: AppSpacing.sectionGap),
                  ..._mealPlans.asMap().entries.map((entry) {
                    return Padding(
                      padding:
                          const EdgeInsets.only(bottom: AppSpacing.gridGap),
                      child: _buildMealCard(entry.key, entry.value),
                    );
                  }),
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }

  Widget _buildTdeeCard(Map<String, double> targets) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.cardPadding),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.cardM),
        border:
            Border.all(color: AppColors.accent.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _statColumn('BMR', '${targets['bmr']?.round() ?? 0}', 'kcal'),
          Container(width: 1, height: 40, color: AppColors.border),
          _statColumn('TDEE', '${targets['tdee']?.round() ?? 0}', 'kcal'),
          Container(width: 1, height: 40, color: AppColors.border),
          _statColumn(
              'TARGET', '${targets['calories']?.round() ?? 0}', 'kcal'),
        ],
      ),
    );
  }

  Widget _statColumn(String label, String value, String unit) {
    return Column(
      children: [
        Text(
          label,
          style: AppTypography.monoXs.copyWith(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.textDim, letterSpacing: 1.2),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: AppTypography.body.copyWith(fontSize: 22, fontWeight: FontWeight.w900, color: AppColors.textPrimary),
        ),
        Text(
          unit,
          style: AppTypography.monoXs.copyWith(fontSize: 10, fontWeight: FontWeight.w400, color: AppColors.textDim),
        ),
      ],
    );
  }

  Widget _buildMacroTargets(Map<String, double> targets) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.cardPadding),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.cardM),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _macroCircle(
              'Protein', '${targets['protein']?.round() ?? 0}g', AppColors.accent),
          _macroCircle(
              'Carbs', '${targets['carbs']?.round() ?? 0}g', AppColors.green),
          _macroCircle(
              'Fat', '${targets['fat']?.round() ?? 0}g', AppColors.purple),
        ],
      ),
    );
  }

  Widget _macroCircle(String label, String value, Color color) {
    return Column(
      children: [
        Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withValues(alpha: 0.08),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Center(
            child: Text(
              value,
              style: AppTypography.body.copyWith(fontWeight: FontWeight.w900, color: color),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: AppTypography.bodySm.copyWith(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textDim),
        ),
      ],
    );
  }

  Widget _buildMealCard(int mealIndex, _MealPlan meal) {
    final totalCals =
        meal.items.fold<int>(0, (sum, i) => sum + i.calories);
    final totalProtein =
        meal.items.fold<int>(0, (sum, i) => sum + i.protein);

    return Container(
      padding: const EdgeInsets.all(AppSpacing.cardPadding),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.cardM),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(meal.name, style: AppTypography.titleS),
              Text(
                '$totalCals kcal \u00B7 P ${totalProtein}g',
                style: AppTypography.bodySm.copyWith(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.accent),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (meal.items.isEmpty)
            Text(
              'No suggestions available',
              style: AppTypography.bodyS
                  .copyWith(color: AppColors.textSecondary),
            )
          else
            ...meal.items.asMap().entries.map((entry) {
              final item = entry.value;
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.name,
                            style: AppTypography.body.copyWith(fontSize: 13, fontWeight: FontWeight.w400, color: AppColors.textPrimary),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            '${item.servingDesc} \u00B7 P${item.protein}g C${item.carbs}g F${item.fat}g',
                            style: AppTypography.monoXs.copyWith(color: AppColors.textDim),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      '${item.calories} kcal',
                      style: AppTypography.bodySm.copyWith(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.warn),
                    ),
                    const SizedBox(width: 6),
                    GestureDetector(
                      onTap: () => _swapItem(mealIndex, entry.key),
                      child: Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: AppColors.input,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: const Icon(
                          Icons.swap_horiz,
                          size: 12,
                          color: AppColors.accent,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }
}

// ── Data Models ─────────────────────────────────────────────────
