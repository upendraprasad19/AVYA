import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/shared/repositories/food_repository.dart';
import 'package:icanbefitter/shared/repositories/user_repository.dart';
import '../providers/nutrition_provider.dart';
import '../providers/diet_plan_provider.dart';

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
  }

  void _generateFreshPlan() {
    final targets = ref.read(macroTargetsProvider);
    final calorieTarget = targets['calories']?.round() ?? 2400;
    final proteinTarget = targets['protein']?.round() ?? 184;

    _mealPlans = [
      _generateMeal(
        'Breakfast',
        (calorieTarget * 0.25).round(),
        (proteinTarget * 0.25).round(),
        ['Staples', 'Dairy'],
      ),
      _generateMeal(
        'Mid-Morning Snack',
        (calorieTarget * 0.10).round(),
        (proteinTarget * 0.15).round(),
        ['Nuts & seeds', 'Fruits'],
      ),
      _generateMeal(
        'Lunch',
        (calorieTarget * 0.30).round(),
        (proteinTarget * 0.30).round(),
        ['Pulses', 'Protein', 'Staples'],
      ),
      _generateMeal(
        'Evening Snack',
        (calorieTarget * 0.10).round(),
        (proteinTarget * 0.10).round(),
        ['Nuts & seeds', 'Beverages'],
      ),
      _generateMeal(
        'Dinner',
        (calorieTarget * 0.25).round(),
        (proteinTarget * 0.20).round(),
        ['Protein', 'Staples', 'Pulses'],
      ),
    ];
    if (mounted) setState(() => _saved = false);
  }

  _MealPlan _generateMeal(
      String name, int targetCals, int targetProtein, List<String> categories) {
    final items = <_PlanFoodItem>[];
    int totalCals = 0;

    // Use date + meal name as seed for daily consistency with variety.
    final now = DateTime.now();
    final mealIndex = _mealPlans.length;
    final seed = DateTime(now.year, now.month, now.day).hashCode + mealIndex;

    for (int catIdx = 0; catIdx < categories.length; catIdx++) {
      final category = categories[catIdx];
      final foods =
          FoodRepository.instance.getByCategory(category).take(20).toList();
      if (foods.isEmpty) continue;

      // Shuffle with deterministic seed for this meal + category.
      foods.shuffle(Random(seed + catIdx));
      final food = foods.first;
      final cals =
          (food['calories_per_100g'] as num?)?.toDouble() ?? 0;
      final protein =
          (food['protein_per_100g'] as num?)?.toDouble() ?? 0;
      final carbs =
          (food['carbs_per_100g'] as num?)?.toDouble() ?? 0;
      final fat = (food['fat_per_100g'] as num?)?.toDouble() ?? 0;
      final servingG =
          (food['standard_serving_g'] as num?)?.toDouble() ?? 100;
      final servingDesc =
          food['standard_serving_desc'] as String? ?? '100g';

      final factor = servingG / 100.0;
      final servingCals = (cals * factor).round();

      items.add(_PlanFoodItem(
        foodId: food['id'] as String? ?? '',
        name: food['name'] as String? ?? 'Unknown',
        servingDesc: servingDesc,
        servingG: servingG,
        calories: servingCals,
        protein: (protein * factor).round(),
        carbs: (carbs * factor).round(),
        fat: (fat * factor).round(),
        category: category,
      ));

      totalCals += servingCals;
      if (totalCals >= targetCals) break;
    }

    return _MealPlan(
      name: name,
      items: items,
      targetCalories: targetCals,
      targetProtein: targetProtein,
    );
  }

  void _swapItem(int mealIndex, int itemIndex) {
    final item = _mealPlans[mealIndex].items[itemIndex];
    final alternatives = FoodRepository.instance
        .getByCategory(item.category)
        .where((f) => (f['id'] as String?) != item.foodId)
        .take(5)
        .toList();

    if (alternatives.isEmpty) return;

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
              ...alternatives.map((food) {
                final foodName = food['name'] as String? ?? 'Unknown';
                final cals =
                    (food['calories_per_100g'] as num?)?.toDouble() ?? 0;
                final servingG =
                    (food['standard_serving_g'] as num?)?.toDouble() ?? 100;
                final servingDesc =
                    food['standard_serving_desc'] as String? ?? '100g';
                final servingCals = (cals * servingG / 100).round();

                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    foodName,
                    style: AppTypography.body.copyWith(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                  ),
                  subtitle: Text(
                    '$servingDesc \u00B7 $servingCals kcal',
                    style: AppTypography.bodySm.copyWith(fontSize: 11, color: AppColors.textDim),
                  ),
                  trailing: const Icon(Icons.swap_horiz,
                      color: AppColors.accent, size: 20),
                  onTap: () {
                    final protein =
                        (food['protein_per_100g'] as num?)?.toDouble() ?? 0;
                    final carbs =
                        (food['carbs_per_100g'] as num?)?.toDouble() ?? 0;
                    final fat =
                        (food['fat_per_100g'] as num?)?.toDouble() ?? 0;
                    final factor = servingG / 100.0;

                    setState(() {
                      _mealPlans[mealIndex].items[itemIndex] = _PlanFoodItem(
                        foodId: food['id'] as String? ?? '',
                        name: foodName,
                        servingDesc: servingDesc,
                        servingG: servingG,
                        calories: servingCals,
                        protein: (protein * factor).round(),
                        carbs: (carbs * factor).round(),
                        fat: (fat * factor).round(),
                        category: item.category,
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

  void _showLoadSavedPlanDialog(Map<String, dynamic> savedPlan) {
    final createdAt = savedPlan['created_at'] as String?;
    String dateLabel = 'a previous session';
    if (createdAt != null) {
      final dt = DateTime.tryParse(createdAt);
      if (dt != null) {
        const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
        dateLabel = '${dt.day} ${months[dt.month - 1]}';
      }
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Saved Diet Plan Found',
          style: AppTypography.body.copyWith(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
        ),
        content: Text(
          'You have a saved plan from $dateLabel. Would you like to load it or generate a fresh one?',
          style: AppTypography.body.copyWith(fontSize: 13, color: AppColors.textDim),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _generateFreshPlan();
            },
            child: Text(
              'Generate New',
              style: AppTypography.body.copyWith(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textDim),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _loadSavedPlan(savedPlan);
            },
            child: Text(
              'Load Saved',
              style: AppTypography.body.copyWith(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.accent),
            ),
          ),
        ],
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
      return _MealPlan(
        name: mealMap['name'] as String? ?? '',
        items: items,
        targetCalories: 0,
        targetProtein: 0,
      );
    }).toList();
    if (mounted) setState(() => _saved = true);
  }

  Future<void> _sharePlanAsPdf() async {
    if (_mealPlans.isEmpty) return;

    try {
    final targets = ref.read(macroTargetsProvider);
    final calorieTarget = targets['calories']?.round() ?? 2400;
    final proteinTarget = targets['protein']?.round() ?? 184;
    final carbTarget = targets['carbs']?.round() ?? 0;
    final fatTarget = targets['fat']?.round() ?? 0;

    final now = DateTime.now();
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    final dateStr = '${now.day} ${months[now.month - 1]} ${now.year}';

    final pdf = pw.Document();

    final headerStyle = pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold);
    final subHeaderStyle = pw.TextStyle(fontSize: 12, color: PdfColors.grey700);
    final mealTitleStyle = pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold);
    final cellStyle = const pw.TextStyle(fontSize: 10);
    final cellBoldStyle = pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold);

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        header: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('ICANBEFITTER Diet Plan', style: headerStyle),
            pw.SizedBox(height: 4),
            pw.Text('Generated on $dateStr', style: subHeaderStyle),
            pw.SizedBox(height: 4),
            pw.Text(
              'Target: $calorieTarget kcal  |  Protein: ${proteinTarget}g  |  Carbs: ${carbTarget}g  |  Fat: ${fatTarget}g',
              style: subHeaderStyle,
            ),
            pw.Divider(),
          ],
        ),
        footer: (context) => pw.Container(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            'Generated by ICANBEFITTER  \u00B7  www.icanbefitter.com',
            style: pw.TextStyle(fontSize: 8, color: PdfColors.grey500),
          ),
        ),
        build: (context) => _mealPlans.map((meal) {
          final totalCals = meal.items.fold<int>(0, (s, i) => s + i.calories);
          final totalProtein = meal.items.fold<int>(0, (s, i) => s + i.protein);

          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.SizedBox(height: 10),
              pw.Text('${meal.name}  ($totalCals kcal, ${totalProtein}g protein)', style: mealTitleStyle),
              pw.SizedBox(height: 6),
              pw.TableHelper.fromTextArray(
                headerStyle: cellBoldStyle,
                cellStyle: cellStyle,
                headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
                cellPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                headers: ['Food', 'Serving', 'Kcal', 'Protein', 'Carbs', 'Fat'],
                data: meal.items.map((item) => [
                  item.name,
                  item.servingDesc,
                  '${item.calories}',
                  '${item.protein}g',
                  '${item.carbs}g',
                  '${item.fat}g',
                ]).toList(),
              ),
              pw.SizedBox(height: 8),
            ],
          );
        }).toList(),
      ),
    );

    final Uint8List bytes = await pdf.save();
    await Share.shareXFiles(
      [XFile.fromData(bytes, name: 'icanbefitter_diet_plan.pdf', mimeType: 'application/pdf')],
      subject: 'ICANBEFITTER Diet Plan',
    );
    } catch (e) {
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
        title: Text(
          'Diet Plan',
          style: AppTypography.body.copyWith(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh,
                color: AppColors.textSecondary, size: 22),
            onPressed: () {
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

class _MealPlan {
  final String name;
  final List<_PlanFoodItem> items;
  final int targetCalories;
  final int targetProtein;

  _MealPlan({
    required this.name,
    required this.items,
    required this.targetCalories,
    required this.targetProtein,
  });
}

class _PlanFoodItem {
  final String foodId;
  final String name;
  final String servingDesc;
  final double servingG;
  final int calories;
  final int protein;
  final int carbs;
  final int fat;
  final String category;

  _PlanFoodItem({
    required this.foodId,
    required this.name,
    required this.servingDesc,
    required this.servingG,
    required this.calories,
    required this.protein,
    required this.carbs,
    required this.fat,
    required this.category,
  });
}
