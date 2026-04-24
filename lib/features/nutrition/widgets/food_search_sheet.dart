import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import '../providers/nutrition_provider.dart';
import 'custom_food_sheet.dart';

/// Bottom sheet for searching the food database (5K items) and logging
/// with adjustable portions. FREE for all users.
///
/// [initialQuery] pre-fills the search input and kicks off a first search
/// — used by the nutrition screen's "From Your Diet Plan" flow so tapping
/// `+ LOG` on an empty slot with a planned meal lands the user on results
/// for that food.
void showFoodSearchSheet(
  BuildContext context, {
  String? mealType,
  String? initialQuery,
}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _FoodSearchSheet(
      initialMealType: mealType,
      initialQuery: initialQuery,
    ),
  );
}

class _FoodSearchSheet extends ConsumerStatefulWidget {
  final String? initialMealType;
  final String? initialQuery;

  const _FoodSearchSheet({this.initialMealType, this.initialQuery});

  @override
  ConsumerState<_FoodSearchSheet> createState() => _FoodSearchSheetState();
}

class _FoodSearchSheetState extends ConsumerState<_FoodSearchSheet> {
  final _searchController = TextEditingController();
  Map<String, dynamic>? _selectedFood;
  double _quantityG = 100;
  String _mealType = 'snacks';

  @override
  void initState() {
    super.initState();
    if (widget.initialMealType != null) {
      _mealType = widget.initialMealType!;
    } else {
      final hour = DateTime.now().hour;
      if (hour < 11) {
        _mealType = 'breakfast';
      } else if (hour < 15) {
        _mealType = 'lunch';
      } else if (hour < 19) {
        _mealType = 'dinner';
      } else {
        _mealType = 'snacks';
      }
    }

    // Pre-fill the search field and kick off a first search so the user
    // lands directly on results for the planned food. Deferred via
    // `addPostFrameCallback` because `foodSearchProvider` is a Notifier
    // and `ref.read(...)` in `initState` is allowed but the listener
    // chain is stabler after the first frame.
    final q = widget.initialQuery?.trim();
    if (q != null && q.isNotEmpty) {
      _searchController.text = q;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref.read(foodSearchProvider.notifier).search(q);
      });
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final searchResults = ref.watch(foodSearchProvider);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: const BoxDecoration(
        color: AppColors.bg,
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(AppRadius.cardL)),
      ),
      child: Column(
        children: [
          // Drag handle
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 8),
            child: Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.textDisabled,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),

          // Title
          Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.screenPadding),
            child: Row(
              children: [
                Text(
                  'Search Food',
                  style: AppTypography.body.copyWith(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close,
                      color: AppColors.textSecondary, size: 22),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),

          // Search field
          Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.screenPadding),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.input,
                borderRadius: BorderRadius.circular(AppRadius.row),
                border: Border.all(color: AppColors.border),
              ),
              child: TextField(
                controller: _searchController,
                autofocus: true,
                onChanged: (q) =>
                    ref.read(foodSearchProvider.notifier).search(q),
                style: AppTypography.body.copyWith(color: AppColors.textPrimary),
                decoration: InputDecoration(
                  hintText: 'Search foods (e.g. paneer tikka, idli)...',
                  hintStyle: AppTypography.body.copyWith(color: AppColors.textDim),
                  border: InputBorder.none,
                  icon: const Icon(Icons.search,
                      color: AppColors.textSecondary, size: 20),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),

          // Content area
          Expanded(
            child: _selectedFood != null
                ? _buildFoodDetail()
                : _buildSearchResults(searchResults),
          ),

          SizedBox(height: bottomInset),
        ],
      ),
    );
  }

  Widget _buildSearchResults(List<Map<String, dynamic>> results) {
    if (_searchController.text.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.search, color: AppColors.textDisabled, size: 40),
            const SizedBox(height: 8),
            Text(
              'Search foods',
              style: AppTypography.body.copyWith(fontSize: 13, color: AppColors.textDim),
            ),
            const SizedBox(height: 20),
            GestureDetector(
              onTap: () {
                Navigator.of(context).pop();
                showCustomFoodSheet(context);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.accent.withValues(alpha: 0.3)),
                  borderRadius: BorderRadius.circular(100),
                  color: AppColors.accent.withValues(alpha: 0.06),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.add, color: AppColors.accent, size: 16),
                    const SizedBox(width: 6),
                    Text(
                      'Create custom food',
                      style: AppTypography.body.copyWith(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.accent),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (results.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'No foods found for "${_searchController.text}"',
              style: AppTypography.body.copyWith(fontSize: 13, color: AppColors.textDim),
            ),
            const SizedBox(height: 16),
            GestureDetector(
              onTap: () {
                Navigator.of(context).pop();
                showCustomFoodSheet(context);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.accent.withValues(alpha: 0.4)),
                  borderRadius: BorderRadius.circular(100),
                  color: AppColors.accent.withValues(alpha: 0.08),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.add, color: AppColors.accent, size: 16),
                    const SizedBox(width: 6),
                    Text(
                      'Create custom food',
                      style: AppTypography.body.copyWith(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.accent),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.screenPadding),
      itemCount: results.length,
      itemBuilder: (context, index) {
        final food = results[index];
        final name = food['name'] as String? ?? 'Unknown';
        final cals =
            (food['calories_per_100g'] as num?)?.toDouble() ?? 0;
        final protein =
            (food['protein_per_100g'] as num?)?.toDouble() ?? 0;
        final servingDesc =
            food['standard_serving_desc'] as String? ?? '100g';
        final servingCals =
            (food['calories_std'] as num?)?.toDouble() ?? cals;

        return GestureDetector(
          onTap: () {
            setState(() {
              _selectedFood = food;
              _quantityG =
                  (food['standard_serving_g'] as num?)?.toDouble() ?? 100;
            });
          },
          child: Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(AppRadius.row),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: AppTypography.body.copyWith(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '$servingDesc \u00B7 P ${protein.round()}g/100g',
                        style: AppTypography.monoXs.copyWith(fontSize: 10, color: AppColors.textDim),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${servingCals.round()} kcal',
                      style: AppTypography.body.copyWith(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.warn),
                    ),
                    Text(
                      'per serving',
                      style: AppTypography.monoXs.copyWith(color: AppColors.textDim),
                    ),
                  ],
                ),
                const SizedBox(width: 8),
                const Icon(Icons.chevron_right,
                    color: AppColors.textSecondary, size: 18),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildFoodDetail() {
    final food = _selectedFood!;
    final name = food['name'] as String? ?? 'Unknown';
    final caloriesPer100 =
        (food['calories_per_100g'] as num?)?.toDouble() ?? 0;
    final proteinPer100 =
        (food['protein_per_100g'] as num?)?.toDouble() ?? 0;
    final carbsPer100 =
        (food['carbs_per_100g'] as num?)?.toDouble() ?? 0;
    final fatPer100 = (food['fat_per_100g'] as num?)?.toDouble() ?? 0;
    final fiberPer100 = (food['fiber_per_100g'] as num?)?.toDouble() ?? 0;
    final servingDesc =
        food['standard_serving_desc'] as String? ?? '100g';
    final servingG =
        (food['standard_serving_g'] as num?)?.toDouble() ?? 100;

    final factor = _quantityG / 100.0;
    final adjustedCals = (caloriesPer100 * factor).round();
    final adjustedProtein = (proteinPer100 * factor).round();
    final adjustedCarbs = (carbsPer100 * factor).round();
    final adjustedFat = (fatPer100 * factor).round();
    final adjustedFiber = (fiberPer100 * factor).round();

    return Padding(
      padding:
          const EdgeInsets.symmetric(horizontal: AppSpacing.screenPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Back button + food name
          Row(
            children: [
              GestureDetector(
                onTap: () => setState(() => _selectedFood = null),
                child: const Icon(Icons.arrow_back,
                    color: AppColors.textSecondary, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  name,
                  style: AppTypography.body.copyWith(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Macro summary card
          Container(
            padding: const EdgeInsets.all(AppSpacing.cardPadding),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(AppRadius.cardM),
              border: Border.all(
                  color: AppColors.accent.withValues(alpha: 0.2)),
            ),
            child: Column(
              children: [
                // Calories
                Text(
                  '$adjustedCals kcal',
                  style: AppTypography.body.copyWith(fontSize: 28, fontWeight: FontWeight.w900, color: AppColors.accent),
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _macroColumn('Protein', '$adjustedProtein g', AppColors.orange),
                    _macroColumn('Carbs', '$adjustedCarbs g', AppColors.blue),
                    _macroColumn('Fat', '$adjustedFat g', AppColors.purple),
                    _macroColumn('Fiber', '$adjustedFiber g', AppColors.green),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Quantity slider (adjustable portions - FREE for all)
          Text(
            'PORTION SIZE',
            style: AppTypography.monoXs.copyWith(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.textDim, letterSpacing: 1.2),
          ),
          const SizedBox(height: 6),

          // Quick portion buttons (count-based for items like eggs, or gram-based)
          Row(
            children: _buildPortionButtons(servingDesc, servingG),
          ),
          const SizedBox(height: 8),

          // Slider
          Row(
            children: [
              Text(
                '${_quantityG.round()}g',
                style: AppTypography.body.copyWith(fontSize: 16, fontWeight: FontWeight.w900, color: AppColors.textPrimary),
              ),
              Expanded(
                child: Slider(
                  value: _quantityG,
                  min: 10,
                  max: 500,
                  divisions: 49,
                  activeColor: AppColors.accent,
                  inactiveColor: AppColors.input,
                  onChanged: (val) => setState(() => _quantityG = val),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Meal type selector
          Text(
            'MEAL TYPE',
            style: AppTypography.monoXs.copyWith(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.textDim, letterSpacing: 1.2),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              _mealTypeChip('breakfast', 'Breakfast'),
              const SizedBox(width: 6),
              _mealTypeChip('lunch', 'Lunch'),
              const SizedBox(width: 6),
              _mealTypeChip('dinner', 'Dinner'),
              const SizedBox(width: 6),
              _mealTypeChip('snacks', 'Snack'),
            ],
          ),

          const Spacer(),

          // Log button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                ref.read(foodLogProvider.notifier).logFood(
                      food: food,
                      mealType: _mealType,
                      quantityG: _quantityG,
                    );
                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Logged $name ($adjustedCals kcal)',
                      style: AppTypography.body.copyWith(fontSize: 13),
                    ),
                    backgroundColor: AppColors.card,
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
              ),
              child: Text(
                '\u2713 Log $name \u2014 $adjustedCals kcal',
                style: AppTypography.body.copyWith(fontWeight: FontWeight.w900, color: Colors.black),
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _macroColumn(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: AppTypography.body.copyWith(fontWeight: FontWeight.w900, color: color),
        ),
        Text(
          label,
          style: AppTypography.monoXs.copyWith(fontSize: 10, color: AppColors.textDim),
        ),
      ],
    );
  }

  /// Generates smart portion buttons. For count-based foods (egg, roti, slice,
  /// piece, cup, scoop, tbsp, tsp, etc.), shows "1 egg, 2 eggs, 3 eggs, 4 eggs".
  /// For gram-based foods, shows the standard serving + 50g/100g/150g/200g.
  List<Widget> _buildPortionButtons(String servingDesc, double servingG) {
    final lower = servingDesc.toLowerCase();
    // Detect count-based servings
    final isCountBased = RegExp(
      r'^\d+\s*(egg|roti|chapati|paratha|slice|piece|pc|cup|scoop|tbsp|tsp|glass|bowl|serving|idli|dosa|puri|vada|samosa|pakora|tikki)',
      caseSensitive: false,
    ).hasMatch(lower);

    if (isCountBased && servingG > 0) {
      // Extract the unit name from serving desc (e.g., "1 large egg" → "egg")
      final unitMatch = RegExp(
        r'\d+\s*(?:small|medium|large|big)?\s*(.*)',
        caseSensitive: false,
      ).firstMatch(servingDesc);
      final unitName = unitMatch?.group(1)?.trim() ?? servingDesc;

      final buttons = <Widget>[];
      for (int i = 1; i <= 5; i++) {
        if (i > 1) buttons.add(const SizedBox(width: 6));
        buttons.add(_portionButton('$i $unitName', servingG * i));
      }
      return buttons;
    }

    // Default: standard serving + gram-based buttons
    return [
      _portionButton(servingDesc, servingG),
      const SizedBox(width: 6),
      _portionButton('50g', 50),
      const SizedBox(width: 6),
      _portionButton('100g', 100),
      const SizedBox(width: 6),
      _portionButton('150g', 150),
      const SizedBox(width: 6),
      _portionButton('200g', 200),
    ];
  }

  Widget _portionButton(String label, double grams) {
    final isSelected = (_quantityG - grams).abs() < 1;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _quantityG = grams),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.accentTint : AppColors.input,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected
                  ? AppColors.accent.withValues(alpha: 0.3)
                  : AppColors.border,
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: AppTypography.monoXs.copyWith(fontWeight: FontWeight.w700, color: isSelected ? AppColors.accent : AppColors.textDim),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }

  Widget _mealTypeChip(String value, String label) {
    final isSelected = _mealType == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _mealType = value),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.accentTint : AppColors.input,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected
                  ? AppColors.accent.withValues(alpha: 0.3)
                  : AppColors.border,
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: AppTypography.monoXs.copyWith(fontSize: 10, fontWeight: FontWeight.w700, color: isSelected ? AppColors.accent : AppColors.textDim),
          ),
        ),
      ),
    );
  }
}
