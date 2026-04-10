import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:icanbefitter/core/constants/app_constants.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:image_picker/image_picker.dart';
import 'package:icanbefitter/core/services/subscription_service.dart';
import 'package:icanbefitter/core/services/usage_counter_service.dart';
import 'package:icanbefitter/shared/widgets/paywall_sheet.dart';
import '../providers/nutrition_provider.dart';

/// Camera-based meal scanning card with usage counter.
///
/// FREE: 3 scans/month. PRO: 3 scans/day with soft cap warning at 2/3.
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
    final isPro = SubscriptionService.instance.isPro();
    final limit = isPro
        ? AppConstants.proScanMealPerDay
        : AppConstants.freeScanMealPerDay;
    final used = UsageCounterService.instance
        .used(AppConstants.featureScanMealPro, isPro);
    final periodLabel = 'today';

    // Soft cap warning for PRO: show at 7/10 used
    final showSoftCap = isPro && used >= 7 && remaining > 0;

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
          // Header row
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
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
                      'Scan Meal',
                      style: GoogleFonts.getFont(
                        'DM Sans',
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    Text(
                      'Point camera at your plate',
                      style: GoogleFonts.getFont(
                        'DM Sans',
                        fontSize: 10,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              // Usage badge
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: remaining > 0
                      ? AppColors.accent.withValues(alpha: 0.08)
                      : AppColors.red.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(AppRadius.badge),
                ),
                child: Text(
                  '${limit - remaining}/$limit used $periodLabel',
                  style: GoogleFonts.getFont(
                    'DM Sans',
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: remaining > 0 ? AppColors.accent : AppColors.red,
                  ),
                ),
              ),
            ],
          ),

          // Soft cap warning
          if (showSoftCap) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.orange.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline,
                      color: AppColors.orange, size: 14),
                  const SizedBox(width: 6),
                  Text(
                    '$used of $limit scans used $periodLabel',
                    style: GoogleFonts.getFont(
                      'DM Sans',
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: AppColors.orange,
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 10),

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
            color: AppColors.accent.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(AppRadius.row),
            border:
                Border.all(color: AppColors.accent.withValues(alpha: 0.2)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.camera_alt, color: AppColors.accent, size: 18),
              const SizedBox(width: 8),
              Text(
                'Take Photo of Your Meal',
                style: GoogleFonts.getFont(
                  'DM Sans',
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.accent,
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
      SubscriptionService.instance.gate(
        AppConstants.featureScanMealPro,
        onPro: () {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Daily scan limit reached. Try again tomorrow.',
                style: GoogleFonts.getFont('DM Sans', fontSize: 13),
              ),
              backgroundColor: AppColors.card,
            ),
          );
        },
        onFree: () =>
            showPaywallSheet(context, feature: 'Scan Meal'),
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
        decoration: const BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadius.cardL),
          ),
          border: Border(
            top: BorderSide(color: AppColors.border, width: 1),
            left: BorderSide(color: AppColors.border, width: 1),
            right: BorderSide(color: AppColors.border, width: 1),
          ),
        ),
        padding: const EdgeInsets.all(AppSpacing.screenPadding),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40, height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: AppColors.textDisabled,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Text(
                'Scan Your Meal',
                style: GoogleFonts.getFont('DM Sans',
                    fontSize: 16, fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary),
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
          borderRadius: BorderRadius.circular(AppRadius.cardS),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                color: AppColors.accentTint,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: AppColors.accent, size: 20),
            ),
            const SizedBox(width: 14),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: GoogleFonts.getFont('DM Sans',
                    fontSize: 14, fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary)),
                Text(subtitle, style: GoogleFonts.getFont('DM Sans',
                    fontSize: 11, color: AppColors.textSecondary)),
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
    ref.read(scanMealProvider.notifier).scanImage(imageBytes);
  }

  Widget _buildError(String error) {
    return Column(
      children: [
        Text(
          error,
          style: GoogleFonts.getFont(
            'DM Sans',
            fontSize: 12,
            color: AppColors.red,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: () => ref.read(scanMealProvider.notifier).clear(),
          child: Text(
            'Try Again',
            style: GoogleFonts.getFont(
              'DM Sans',
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.accent,
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

  void _save() {
    if (_saving) return;
    final liveItems = _items.where((i) => i.hasContent).toList();
    if (liveItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Add at least one item with a name before saving.',
            style: GoogleFonts.getFont('DM Sans', fontSize: 13),
          ),
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }
    setState(() => _saving = true);

    final now = DateTime.now();
    final dateStr =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final id = 'nlog_${now.millisecondsSinceEpoch}';

    HiveService.instance.nutritionBox.put(id, {
      'id': id,
      'date': dateStr,
      'meal_type': 'snacks',
      'food_name': _mealNameCtrl.text.trim().isEmpty
          ? 'Scanned Meal'
          : _mealNameCtrl.text.trim(),
      'total_calories': _totalKcal,
      'total_protein': _sumMacro((i) => i.protein),
      'total_carbs': _sumMacro((i) => i.carbs),
      'total_fat': _sumMacro((i) => i.fat),
      'total_fiber': _sumMacro((i) => i.fiber),
      'items': liveItems.map((i) => i.toMap()).toList(),
      'created_at': now.toIso8601String(),
      'source': 'scan_meal',
    });

    ref.invalidate(dailyNutritionProvider);

    final messenger = ScaffoldMessenger.of(context);
    ref.read(scanMealProvider.notifier).clear();
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Meal saved ✓'),
        duration: Duration(seconds: 1),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Editable meal name + live total
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: TextField(
                controller: _mealNameCtrl,
                onChanged: (_) => setState(() {}),
                style: GoogleFonts.getFont(
                  'DM Sans',
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
                decoration: _fieldDecoration('Meal name'),
              ),
            ),
            const SizedBox(width: 10),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.accent.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(AppRadius.badge),
              ),
              child: Text(
                '$_totalKcal kcal',
                style: GoogleFonts.getFont(
                  'DM Sans',
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: AppColors.accent,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // Items list
        ..._items.map(_buildItemRow),
        const SizedBox(height: 8),

        // + Add item
        GestureDetector(
          onTap: _addItem,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.input,
              borderRadius: BorderRadius.circular(AppRadius.cardS),
              border: Border.all(
                color: AppColors.accent.withValues(alpha: 0.3),
                width: 1,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.add, size: 14, color: AppColors.accent),
                const SizedBox(width: 4),
                Text(
                  'Add Item',
                  style: GoogleFonts.getFont(
                    'DM Sans',
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.accent,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        // Save / Discard
        Row(
          children: [
            Expanded(
              child: GestureDetector(
                onTap: _saving ? null : _save,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.accent,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '\u2713 Save',
                    style: GoogleFonts.getFont(
                      'DM Sans',
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      color: Colors.black,
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
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.border),
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                child: Text(
                  'Discard',
                  style: GoogleFonts.getFont(
                    'DM Sans',
                    fontSize: 12,
                    color: AppColors.textSecondary,
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
                  style: GoogleFonts.getFont(
                    'DM Sans',
                    fontSize: 12,
                    color: AppColors.textPrimary,
                  ),
                  decoration: _fieldDecoration('Food name'),
                ),
              ),
              const SizedBox(width: 6),
              SizedBox(
                width: 58,
                child: TextField(
                  controller: item.kcalCtrl,
                  onChanged: (_) => setState(() {}),
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.getFont(
                    'DM Sans',
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.orange,
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
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              GestureDetector(
                onTap: () => _removeItem(item),
                child: const Padding(
                  padding: EdgeInsets.all(6),
                  child: Icon(Icons.close, size: 16, color: AppColors.red),
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
                        item.carbsCtrl, 'C g', AppColors.blue)),
                const SizedBox(width: 6),
                Expanded(
                    child:
                        _macroField(item.fatCtrl, 'F g', AppColors.orange)),
                const SizedBox(width: 6),
                Expanded(
                    child: _macroField(
                        item.fiberCtrl, 'Fi g', AppColors.green)),
              ],
            ),
          ],
        ],
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
      style: GoogleFonts.getFont(
        'DM Sans',
        fontSize: 11,
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
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.cardS),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.cardS),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.cardS),
        borderSide:
            const BorderSide(color: AppColors.accent, width: 1.0),
      ),
      hintText: hint,
      hintStyle: GoogleFonts.getFont(
        'DM Sans',
        fontSize: 10,
        color: AppColors.textSecondary,
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
