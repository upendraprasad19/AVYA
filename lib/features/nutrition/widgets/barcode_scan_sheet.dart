import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:icanbefitter/core/services/barcode_service.dart';
import 'package:icanbefitter/core/services/nutrition_write_service.dart';
import 'package:icanbefitter/core/services/nutrition_write_source.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/features/nutrition/widgets/custom_food_sheet.dart';

/// Opens the barcode scanner as a full-screen bottom sheet.
void showBarcodeScanSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _BarcodeScanSheet(),
  );
}

class _BarcodeScanSheet extends ConsumerStatefulWidget {
  const _BarcodeScanSheet();

  @override
  ConsumerState<_BarcodeScanSheet> createState() => _BarcodeScanSheetState();
}

class _BarcodeScanSheetState extends ConsumerState<_BarcodeScanSheet> {
  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.92,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      builder: (_, scroll) => Container(
        decoration: const BoxDecoration(
          color: AppColors.bg,
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
        child: Column(
          children: [
            // Handle
            Container(
              margin: const EdgeInsets.only(top: 10, bottom: 4),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
              child: Row(
                children: [
                  Text(
                    'Scan Barcode',
                    style: AppTypography.body.copyWith(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: AppColors.input,
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: const Icon(Icons.close,
                          color: AppColors.textSecondary, size: 16),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: BarcodeBody(
                onLogged: () => Navigator.of(context).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

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
  final _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    facing: CameraFacing.back,
  );

  bool _loading = false;
  bool _scanned = false;
  BarcodeFood? _food;
  String? _error;
  double _servingG = 100;
  String _mealType = 'snacks';

  @override
  void initState() {
    super.initState();
    final hour = DateTime.now().hour;
    if (hour < 11) {
      _mealType = 'breakfast';
    } else if (hour < 15) {
      _mealType = 'lunch';
    } else if (hour < 19) {
      _mealType = 'dinner';
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_scanned || _loading) return;
    final barcode = capture.barcodes.firstOrNull?.rawValue;
    if (barcode == null) return;

    setState(() {
      _loading = true;
      _scanned = true;
      _error = null;
    });
    await _controller.stop();

    final food = await BarcodeService.instance.lookup(barcode);

    if (!mounted) return;
    setState(() {
      _loading = false;
      _food = food;
      _servingG = food?.servingG ?? 100;
      if (food == null) {
        _error = 'Product not found in database.\nTry searching by name.';
      }
    });
  }

  void _reset() {
    setState(() {
      _scanned = false;
      _loading = false;
      _food = null;
      _error = null;
    });
    _controller.start();
  }

  Future<void> _logFood() async {
    final food = _food;
    if (food == null) return;

    // Plan C-12: route through NutritionWriteService.logMeal so per-item
    // rows reach nutrition_log_items + provider invalidation runs.
    // Barcode source is free + unlimited (no counter increment).
    final result = await NutritionWriteService.instance.logMeal(
      date: DateTime.now(),
      mealType: _mealType,
      items: [
        FoodItem(
          name: food.brand != null
              ? '${food.name} (${food.brand})'
              : food.name,
          quantityG: _servingG,
          calories: food.caloriesForServing(_servingG),
          protein: food.proteinForServing(_servingG),
          carbs: food.carbsForServing(_servingG),
          fat: food.fatForServing(_servingG),
          fiber: food.fiberForServing(_servingG),
        ),
      ],
      source: NutritionWriteSource.barcode,
    );

    if (!mounted) return;
    if (result.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${food.name} logged ✓',
              style: AppTypography.body.copyWith(fontSize: 13)),
          backgroundColor: AppColors.card,
          duration: const Duration(seconds: 2),
        ),
      );
      widget.onLogged();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Could not log: ${result.errorMessage ?? "unknown error"}',
            style: AppTypography.body.copyWith(fontSize: 13),
          ),
          backgroundColor: AppColors.card,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return _food != null ? _buildFoodResult() : _buildScanner();
  }

  Widget _buildScanner() {
    if (kIsWeb) {
      return _buildWebFallback();
    }
    return Column(
      children: [
        // Camera viewfinder
        Expanded(
          child: Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.card),
                child: MobileScanner(
                  controller: _controller,
                  onDetect: _onDetect,
                ),
              ),
              // Scan frame overlay
              Center(
                child: Container(
                  width: 240,
                  height: 160,
                  decoration: BoxDecoration(
                    border: Border.all(
                        color: AppColors.accent, width: 2.5),
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              if (_loading)
                Container(
                  color: Colors.black54,
                  child: const Center(
                    child: CircularProgressIndicator(
                      color: AppColors.accent,
                      strokeWidth: 2.5,
                    ),
                  ),
                ),
            ],
          ),
        ),

        // Status text
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
          child: _error != null
              ? Column(
                  children: [
                    Text(
                      _error!,
                      style: AppTypography.body
                          .copyWith(fontSize: 13, color: AppColors.textDim),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    GestureDetector(
                      onTap: _reset,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 12),
                        decoration: BoxDecoration(
                          color: AppColors.accentTint,
                          border: Border.all(
                              color: AppColors.accent.withValues(alpha: 0.3)),
                          borderRadius: BorderRadius.circular(100),
                        ),
                        child: Text(
                          'Scan Again',
                          style: AppTypography.body.copyWith(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: AppColors.accent),
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: () {
                        widget.onLogged();
                        showCustomFoodSheet(context);
                      },
                      child: Container(
                        margin: const EdgeInsets.only(top: 8),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 12),
                        decoration: BoxDecoration(
                          border: Border.all(color: AppColors.border),
                          borderRadius: BorderRadius.circular(100),
                        ),
                        child: Text("Add manually",
                            style: AppTypography.body.copyWith(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textDim)),
                      ),
                    ),
                  ],
                )
              : Text(
                  'Point camera at the barcode on the packaging',
                  style: AppTypography.body
                      .copyWith(fontSize: 13, color: AppColors.textDim),
                  textAlign: TextAlign.center,
                ),
        ),
      ],
    );
  }

  Widget _buildWebFallback() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: AppColors.accentTint,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(Icons.phone_android_rounded,
                color: AppColors.accent, size: 36),
          ),
          const SizedBox(height: 20),
          Text(
            'Barcode scanning requires\nthe mobile app',
            style: AppTypography.body.copyWith(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),
          Text(
            'Download ICANBEFITTER on Android to scan\nproduct barcodes with your camera.',
            style: AppTypography.body
                .copyWith(fontSize: 13, color: AppColors.textDim),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          GestureDetector(
            onTap: widget.onLogged,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 28, vertical: 13),
              decoration: BoxDecoration(
                color: AppColors.accent,
                borderRadius: BorderRadius.circular(100),
              ),
              child: Text(
                'Got it',
                style: AppTypography.body.copyWith(
                    fontWeight: FontWeight.w900, color: Colors.black),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFoodResult() {
    final food = _food!;
    final cals = food.caloriesForServing(_servingG).round();
    final protein = food.proteinForServing(_servingG).round();
    final carbs = food.carbsForServing(_servingG).round();
    final fat = food.fatForServing(_servingG).round();

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Found badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.green.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(100),
            ),
            child: Text(
              '✓ Product found',
              style: AppTypography.bodySm.copyWith(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ok),
            ),
          ),
          const SizedBox(height: 10),

          // Product name
          Text(
            food.name,
            style: AppTypography.body.copyWith(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary),
          ),
          if (food.brand != null) ...[
            const SizedBox(height: 2),
            Text(
              food.brand!,
              style: AppTypography.body
                  .copyWith(fontSize: 13, color: AppColors.textDim),
            ),
          ],
          const SizedBox(height: 16),

          // Serving size slider
          _buildServingSection(food),
          const SizedBox(height: 16),

          // Macros
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                _macroPill('$cals', 'kcal', AppColors.accent),
                const SizedBox(width: 8),
                _macroPill('${protein}g', 'protein', AppColors.blue),
                const SizedBox(width: 8),
                _macroPill('${carbs}g', 'carbs', AppColors.orange),
                const SizedBox(width: 8),
                _macroPill('${fat}g', 'fat', AppColors.purple),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Meal type selector
          _buildMealTypeSelector(),
          const SizedBox(height: 16),

          // Action buttons
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: _logFood,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: AppColors.accent,
                      borderRadius: BorderRadius.circular(100),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.accent.withValues(alpha: 0.3),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '✓ Log Food',
                      style: AppTypography.body.copyWith(
                          fontWeight: FontWeight.w900, color: Colors.black),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              GestureDetector(
                onTap: _reset,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.border),
                    borderRadius: BorderRadius.circular(100),
                  ),
                  child: Text(
                    'Rescan',
                    style: AppTypography.body
                        .copyWith(fontSize: 13, color: AppColors.textDim),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildServingSection(BarcodeFood food) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Serving size',
                style: AppTypography.body.copyWith(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary)),
            Text('${_servingG.round()}g',
                style: AppTypography.body.copyWith(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    color: AppColors.accent)),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: AppColors.accent,
            inactiveTrackColor: AppColors.input,
            thumbColor: AppColors.accent,
            overlayColor: AppColors.accent.withValues(alpha: 0.15),
            trackHeight: 4,
          ),
          child: Slider(
            value: _servingG,
            min: 10,
            max: 500,
            divisions: 49,
            onChanged: (v) => setState(() => _servingG = v),
          ),
        ),
        if (food.servingDesc != null)
          Text(
            'Typical serving: ${food.servingDesc}',
            style: AppTypography.monoXs
                .copyWith(fontSize: 10, color: AppColors.textDim),
          ),
      ],
    );
  }

  Widget _buildMealTypeSelector() {
    const types = ['breakfast', 'lunch', 'dinner', 'snacks'];
    const labels = ['Breakfast', 'Lunch', 'Dinner', 'Snacks'];

    return Row(
      children: List.generate(types.length, (i) {
        final isActive = _mealType == types[i];
        return Expanded(
          child: GestureDetector(
            onTap: () => setState(() => _mealType = types[i]),
            child: Container(
              margin: EdgeInsets.only(right: i < types.length - 1 ? 6 : 0),
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
                labels[i],
                style: AppTypography.monoXs.copyWith(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: isActive ? AppColors.accent : AppColors.textDim),
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _macroPill(String value, String label, Color color) {
    return Expanded(
      child: Column(
        children: [
          Text(value,
              style: AppTypography.body.copyWith(
                  fontSize: 15, fontWeight: FontWeight.w900, color: color)),
          Text(label,
              style: AppTypography.monoXs
                  .copyWith(color: AppColors.textDim)),
        ],
      ),
    );
  }
}
