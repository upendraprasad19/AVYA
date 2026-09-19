import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:icanbefitter/core/constants/app_constants.dart';
import 'package:icanbefitter/core/services/nutrition_write_service.dart';
import 'package:icanbefitter/core/services/nutrition_write_source.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:image_picker/image_picker.dart';
import 'package:icanbefitter/core/services/subscription_service.dart';
import 'package:icanbefitter/core/services/usage_counter_service.dart';
import 'package:icanbefitter/shared/widgets/paywall_sheet.dart';
import 'package:icanbefitter/shared/widgets/wardroom/wardroom.dart';
import 'package:icanbefitter/features/profile/providers/profile_provider.dart';
import '../providers/nutrition_provider.dart';
import 'ai_breakdown_card.dart' show MealSlotChip;

/// Camera-based meal scanning card with usage counter.
///
/// FREE: 3 scans/day. PRO: 10 scans/day (soft-cap warn at 7).
class ScanMealSection extends ConsumerStatefulWidget {
  const ScanMealSection({super.key});

  @override
  ConsumerState<ScanMealSection> createState() => _ScanMealSectionState();
}

class _ScanMealSectionState extends ConsumerState<ScanMealSection> {
  @override
  Widget build(BuildContext context) {
    final scanState = ref.watch(scanMealProvider);
    final remaining = ref.watch(scanMealRemainingProvider);
    final isPro = ref.watch(subscriptionInfoProvider).isPro;
    final limit = isPro
        ? AppConstants.proScanMealPerDay
        : AppConstants.freeScanMealPerDay;
    final used = UsageCounterService.instance
        .used(AppConstants.featureScanMealPro, isPro);

    // Soft cap warning for PRO: show at 7/10 used
    final showSoftCap = isPro && used >= 7 && remaining > 0;

    return WardCard(
      padding: const EdgeInsets.all(AppSpacing.cardPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: AppColors.accentSoft,
                  borderRadius: BorderRadius.circular(AppRadius.sharp),
                ),
                child: const Icon(Icons.camera_alt_outlined,
                    color: AppColors.accent, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'SCAN MEAL',
                      style: AppTypography.mono.copyWith(
                        color: AppColors.textMute,
                        letterSpacing: 2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Point camera at your plate',
                      style: AppTypography.bodySm.copyWith(
                        color: AppColors.textDim,
                      ),
                    ),
                  ],
                ),
              ),
              // Usage chip
              WardChip(
                label: '${limit - remaining}/$limit TODAY',
                tone: remaining > 0 ? WardChipTone.gold : WardChipTone.bad,
              ),
            ],
          ),

          // Soft cap warning
          if (showSoftCap) ...[
            const SizedBox(height: 10),
            WardChip(
              label: '$used OF $limit SCANS USED TODAY',
              tone: WardChipTone.warn,
            ),
          ],

          const SizedBox(height: 12),

          // Scan button or result
          if (scanState.isScanning)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: CircularProgressIndicator(
                  color: AppColors.accent,
                  strokeWidth: 2,
                ),
              ),
            )
          else if (scanState.error != null)
            _buildError(scanState.error!)
          else if (scanState.result != null)
            // Keyed by identity so a fresh scan rebuilds the editor state
            // cleanly instead of carrying over old controllers.
            _ScanResultEditor(
              key: ObjectKey(scanState.result),
              initialResult: scanState.result!,
            )
          else
            _buildScanButton(context, remaining),
        ],
      ),
    );
  }

  Widget _buildScanButton(BuildContext context, int remaining) {
    return SizedBox(
      width: double.infinity,
      child: GestureDetector(
        onTap: () => _handleScan(context, remaining),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.accentSoft,
            borderRadius: BorderRadius.circular(AppRadius.sharp),
            border: Border.all(
                color: AppColors.accent.withValues(alpha: 0.35), width: 2),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.camera_alt, color: AppColors.accent, size: 18),
              const SizedBox(width: 8),
              Text(
                'TAKE PHOTO',
                style: AppTypography.mono.copyWith(
                  color: AppColors.accent,
                  letterSpacing: 2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleScan(BuildContext context, int remaining) async {
    if (remaining <= 0) {
      await SubscriptionService.instance.gateAndVerify(
        AppConstants.featureScanMealPro,
        onPro: () {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Daily scan limit reached. Try again tomorrow.',
                style: AppTypography.body,
              ),
              backgroundColor: AppColors.card,
            ),
          );
        },
        onFree: () => showPaywallSheet(context, feature: 'Scan Meal'),
      );
      return;
    }

    if (kIsWeb) {
      // Web: go straight to gallery (camera not available)
      await _pickAndScan(ImageSource.gallery);
      return;
    }

    // Native: show Camera / Gallery bottom sheet
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadius.card),
          ),
          border: const Border(
            top: BorderSide(color: AppColors.line2, width: 1),
            left: BorderSide(color: AppColors.line2, width: 1),
            right: BorderSide(color: AppColors.line2, width: 1),
          ),
        ),
        padding: const EdgeInsets.all(AppSpacing.gutter),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: AppColors.line2,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Text(
                'SCAN YOUR MEAL',
                style: AppTypography.mono.copyWith(
                  color: AppColors.textMute,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 16),
              _sourceOption(ctx, Icons.camera_alt, 'Camera',
                  'Take a photo now', ImageSource.camera),
              const SizedBox(height: 8),
              _sourceOption(ctx, Icons.photo_library, 'Gallery',
                  'Choose from photos', ImageSource.gallery),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );

    if (source != null) await _pickAndScan(source);
  }

  Widget _sourceOption(BuildContext ctx, IconData icon, String label,
      String subtitle, ImageSource source) {
    return GestureDetector(
      onTap: () => Navigator.of(ctx).pop(source),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.input,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: AppColors.line2),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.accentSoft,
                borderRadius: BorderRadius.circular(AppRadius.sharp),
              ),
              child: Icon(icon, color: AppColors.accent, size: 20),
            ),
            const SizedBox(width: 14),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: AppTypography.h3),
                Text(subtitle,
                    style: AppTypography.bodySm
                        .copyWith(color: AppColors.textDim)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickAndScan(ImageSource source) async {
    final picker = ImagePicker();
    final image = await picker.pickImage(source: source);
    if (image == null) return;

    final imageBytes = await image.readAsBytes();
    // Quota increment moved to ScanMealNotifier.scanImage() success path
    // so failures don't consume a daily attempt.
    unawaited(ref.read(scanMealProvider.notifier).scanImage(imageBytes));
  }

  Widget _buildError(String error) {
    return Column(
      children: [
        Text(
          error,
          style: AppTypography.bodySm.copyWith(color: AppColors.bad),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: () => ref.read(scanMealProvider.notifier).clear(),
          child: Text(
            'TRY AGAIN',
            style: AppTypography.mono.copyWith(
              color: AppColors.accent,
              letterSpacing: 2,
            ),
          ),
        ),
      ],
    );
  }
}

/// Editable scan result: makes every item mutable so the user can correct
/// AI mistakes (wrong food, wrong qty, wrong kcal) before saving. The total
/// is ALWAYS a live sum of items (with Atwater fallback per-item when kcal
/// is missing) — fixes the 0-kcal save bug where the top-level total from
/// the AI response was often missing while per-item kcal was populated.
class _ScanResultEditor extends ConsumerStatefulWidget {
  final Map<String, dynamic> initialResult;
  const _ScanResultEditor({super.key, required this.initialResult});

  @override
  ConsumerState<_ScanResultEditor> createState() => _ScanResultEditorState();
}

class _ScanResultEditorState extends ConsumerState<_ScanResultEditor> {
  late final TextEditingController _mealNameCtrl;
  final List<_EditableItem> _items = [];
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _mealNameCtrl = TextEditingController(
      text: (widget.initialResult['meal_name'] as String?) ?? 'Scanned Meal',
    );
    final rawItems = (widget.initialResult['items'] as List<dynamic>?) ?? [];
    for (final raw in rawItems) {
      if (raw is Map) {
        _items.add(_EditableItem.fromMap(Map<String, dynamic>.from(raw)));
      }
    }
    // Ensure at least one row so the user has something to edit even if the
    // AI returned an empty items array.
    if (_items.isEmpty) {
      _items.add(_EditableItem.empty());
    }
  }

  @override
  void dispose() {
    _mealNameCtrl.dispose();
    for (final item in _items) {
      item.dispose();
    }
    super.dispose();
  }

  int get _totalKcal {
    var sum = 0;
    for (final item in _items) {
      if (!item.hasContent) continue;
      sum += item.effectiveKcal().round();
    }
    return sum;
  }

  int _sumMacro(double Function(_EditableItem) fn) {
    var sum = 0.0;
    for (final item in _items) {
      if (!item.hasContent) continue;
      sum += fn(item);
    }
    return sum.round();
  }

  void _addItem() {
    setState(() => _items.add(_EditableItem.empty()));
  }

  void _removeItem(_EditableItem item) {
    setState(() {
      _items.remove(item);
      item.dispose();
      if (_items.isEmpty) {
        // Keep at least one row so Save doesn't end up writing nothing.
        _items.add(_EditableItem.empty());
      }
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    final liveItems = _items.where((i) => i.hasContent).toList();
    if (liveItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Add at least one item with a name before saving.',
            style: AppTypography.body,
          ),
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }
    setState(() => _saving = true);

    // Slot — inferred default or user-override via the MealSlotChip shown
    // at the top of the editor (PR Part C.3, 2026-04-24). Reads the same
    // `mealTypeProvider` the AI breakdown card writes to, so a scan made
    // right after an AI log stays on the same slot unless the user
    // flips it.
    final mealType = ref.read(mealTypeProvider);

    // Plan C-11: route through NutritionWriteService.logMeal so per-item
    // rows reach nutrition_log_items + featureScanMealPro auto-increments
    // (closes obs #23 — cloud previously had a top-level row but ZERO
    // nutrition_log_items rows because scan path bypassed projection).
    final items = liveItems
        .map((i) => FoodItem(
              name: i.nameCtrl.text.trim(),
              // Test #11 M4: scan editor has no per-item gram field.
              // Use 100.0 (canonical "per 100g" sentinel) so cloud
              // nutrition_log_items.quantity_g is non-zero and meaningful.
              quantityG: 100.0,
              calories: i.effectiveKcal(),
              protein: i.protein,
              carbs: i.carbs,
              fat: i.fat,
              fiber: i.fiber,
            ))
        .toList();

    final result = await NutritionWriteService.instance.logMeal(
      date: DateTime.now(),
      mealType: mealType,
      items: items,
      overrideTotalCals: _totalKcal,
      overrideTotalProtein: _sumMacro((i) => i.protein),
      source: NutritionWriteSource.scan,
    );

    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    if (result.success) {
      ref.read(scanMealProvider.notifier).clear();
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Meal saved ✓'),
          duration: Duration(seconds: 1),
        ),
      );
    } else {
      setState(() => _saving = false);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Save failed: ${result.errorMessage ?? "unknown error"}',
            style: AppTypography.body,
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Watch so the chip rebuilds when the user picks a different slot from
    // the popup menu.
    final slot = ref.watch(mealTypeProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Slot chip row — Logging to: 🍱 LUNCH ▾
        Row(
          children: [
            Text(
              'LOGGING TO',
              style: AppTypography.monoXs.copyWith(
                color: AppColors.textMute,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(width: 8),
            MealSlotChip(
              slot: slot,
              onSelected: (s) =>
                  ref.read(mealTypeProvider.notifier).select(s),
            ),
          ],
        ),
        const SizedBox(height: 10),
        // Editable meal name + live total
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: TextField(
                controller: _mealNameCtrl,
                onChanged: (_) => setState(() {}),
                style: AppTypography.h3,
                decoration: _fieldDecoration('Meal name'),
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '$_totalKcal',
                  style: AppTypography.h2.copyWith(
                    color: AppColors.accent,
                  ),
                ),
                Text(
                  'KCAL',
                  style: AppTypography.monoXs.copyWith(
                    color: AppColors.textMute,
                    letterSpacing: 1.5,
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),
        const WardRule(gold: true, margin: EdgeInsets.zero),
        const SizedBox(height: 10),

        // Items list
        ..._items.map(_buildItemRow),
        const SizedBox(height: 8),

        // + Add item — sharp 2-px accent slab
        GestureDetector(
          onTap: _addItem,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.input,
              borderRadius: BorderRadius.circular(AppRadius.sharp),
              border: Border.all(
                color: AppColors.accent.withValues(alpha: 0.35),
                width: 2,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.add, size: 14, color: AppColors.accent),
                const SizedBox(width: 6),
                Text(
                  'ADD ITEM',
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

        // Save / Discard — sharp slabs
        Row(
          children: [
            Expanded(
              child: GestureDetector(
                onTap: _saving ? null : _save,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  decoration: BoxDecoration(
                    color: AppColors.accent,
                    borderRadius: BorderRadius.circular(AppRadius.sharp),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    'SAVE',
                    style: AppTypography.mono.copyWith(
                      color: AppColors.bgDeep,
                      letterSpacing: 2,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => ref.read(scanMealProvider.notifier).clear(),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.line2),
                  borderRadius: BorderRadius.circular(AppRadius.sharp),
                ),
                child: Text(
                  'DISCARD',
                  style: AppTypography.mono.copyWith(
                    color: AppColors.textDim,
                    letterSpacing: 2,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildItemRow(_EditableItem item) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: WardCard(
        variant: WardCardVariant.inset,
        padding: const EdgeInsets.all(8),
        child: Column(
          children: [
            // Compact row: name | kcal | expand | delete
            Row(
              children: [
                Expanded(
                  flex: 5,
                  child: TextField(
                    controller: item.nameCtrl,
                    onChanged: (_) => setState(() {}),
                    style: AppTypography.body,
                    decoration: _fieldDecoration('Food name'),
                  ),
                ),
                const SizedBox(width: 6),
                SizedBox(
                  width: 64,
                  child: TextField(
                    controller: item.kcalCtrl,
                    onChanged: (_) => setState(() {}),
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    style: AppTypography.body.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppColors.accent,
                    ),
                    decoration: _fieldDecoration('kcal'),
                  ),
                ),
                GestureDetector(
                  onTap: () =>
                      setState(() => item.expanded = !item.expanded),
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Icon(
                      item.expanded ? Icons.expand_less : Icons.expand_more,
                      size: 18,
                      color: AppColors.textDim,
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () => _removeItem(item),
                  child: Padding(
                    padding: const EdgeInsets.only(left: 2),
                    child: WardChip(
                      label: '',
                      tone: WardChipTone.bad,
                      leading: const Icon(Icons.close,
                          size: 10, color: AppColors.bad),
                    ),
                  ),
                ),
              ],
            ),
            // Expanded macros row
            if (item.expanded) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                      child: _macroField(
                          item.proteinCtrl, 'P g', AppColors.accent)),
                  const SizedBox(width: 6),
                  Expanded(
                      child: _macroField(
                          item.carbsCtrl, 'C g', AppColors.warn)),
                  const SizedBox(width: 6),
                  Expanded(
                      child:
                          _macroField(item.fatCtrl, 'F g', AppColors.bad)),
                  const SizedBox(width: 6),
                  Expanded(
                      child: _macroField(
                          item.fiberCtrl, 'Fi g', AppColors.ok)),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _macroField(
      TextEditingController ctrl, String label, Color color) {
    return TextField(
      controller: ctrl,
      onChanged: (_) => setState(() {}),
      keyboardType: TextInputType.number,
      textAlign: TextAlign.center,
      style: AppTypography.bodySm.copyWith(
        fontWeight: FontWeight.w700,
        color: color,
      ),
      decoration: _fieldDecoration(label),
    );
  }

  InputDecoration _fieldDecoration(String hint) {
    return InputDecoration(
      isDense: true,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      filled: true,
      fillColor: AppColors.input,
      border: const UnderlineInputBorder(
        borderSide: BorderSide(color: AppColors.line2),
      ),
      enabledBorder: const UnderlineInputBorder(
        borderSide: BorderSide(color: AppColors.line2),
      ),
      focusedBorder: const UnderlineInputBorder(
        borderSide: BorderSide(color: AppColors.accent, width: 1.5),
      ),
      hintText: hint,
      hintStyle: AppTypography.bodySm.copyWith(
        color: AppColors.textMute,
      ),
    );
  }
}

/// One editable scanned item (name + kcal + macros) with Atwater fallback.
class _EditableItem {
  final TextEditingController nameCtrl;
  final TextEditingController kcalCtrl;
  final TextEditingController proteinCtrl;
  final TextEditingController carbsCtrl;
  final TextEditingController fatCtrl;
  final TextEditingController fiberCtrl;
  bool expanded;

  _EditableItem({
    required this.nameCtrl,
    required this.kcalCtrl,
    required this.proteinCtrl,
    required this.carbsCtrl,
    required this.fatCtrl,
    required this.fiberCtrl,
  }) : expanded = false;

  factory _EditableItem.fromMap(Map<String, dynamic> map) {
    String numStr(dynamic v) {
      if (v == null) return '';
      if (v is num) {
        if (v == 0) return '';
        return v == v.truncateToDouble()
            ? v.toInt().toString()
            : v.toString();
      }
      return v.toString();
    }

    return _EditableItem(
      nameCtrl: TextEditingController(text: (map['name'] as String?) ?? ''),
      kcalCtrl: TextEditingController(text: numStr(map['calories'])),
      proteinCtrl: TextEditingController(text: numStr(map['protein'])),
      carbsCtrl: TextEditingController(text: numStr(map['carbs'])),
      fatCtrl: TextEditingController(text: numStr(map['fat'])),
      fiberCtrl: TextEditingController(text: numStr(map['fiber'])),
    );
  }

  factory _EditableItem.empty() {
    return _EditableItem(
      nameCtrl: TextEditingController(),
      kcalCtrl: TextEditingController(),
      proteinCtrl: TextEditingController(),
      carbsCtrl: TextEditingController(),
      fatCtrl: TextEditingController(),
      fiberCtrl: TextEditingController(),
    );
  }

  bool get hasContent => nameCtrl.text.trim().isNotEmpty;

  double get kcalRaw => double.tryParse(kcalCtrl.text.trim()) ?? 0;
  double get protein => double.tryParse(proteinCtrl.text.trim()) ?? 0;
  double get carbs => double.tryParse(carbsCtrl.text.trim()) ?? 0;
  double get fat => double.tryParse(fatCtrl.text.trim()) ?? 0;
  double get fiber => double.tryParse(fiberCtrl.text.trim()) ?? 0;

  /// Atwater fallback: if the user or AI left kcal blank but macros are
  /// present, estimate kcal from 4/4/9. Otherwise use the entered kcal.
  double effectiveKcal() {
    final raw = kcalRaw;
    if (raw > 0) return raw;
    return (protein * 4) + (carbs * 4) + (fat * 9);
  }

  Map<String, dynamic> toMap() => {
        'name': nameCtrl.text.trim(),
        'calories': effectiveKcal().round(),
        'protein': protein.round(),
        'carbs': carbs.round(),
        'fat': fat.round(),
        'fiber': fiber.round(),
      };

  void dispose() {
    nameCtrl.dispose();
    kcalCtrl.dispose();
    proteinCtrl.dispose();
    carbsCtrl.dispose();
    fatCtrl.dispose();
    fiberCtrl.dispose();
  }
}
