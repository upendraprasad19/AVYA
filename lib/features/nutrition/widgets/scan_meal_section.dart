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
  bool _saving = false;

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
            _buildResult(context, scanState.result!)
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

  Widget _buildResult(BuildContext context, Map<String, dynamic> result) {
    final items = (result['items'] as List<dynamic>?) ?? [];
    final totalKcal = (result['total_calories'] as num?)?.toInt() ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Result header
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Scan Result',
              style: GoogleFonts.getFont(
                'DM Sans',
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            Text(
              '$totalKcal kcal',
              style: GoogleFonts.getFont(
                'DM Sans',
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.accent,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // Items list
        ...items.map((item) {
          final name = item['name'] as String? ?? 'Unknown';
          final cals = (item['calories'] as num?)?.toInt() ?? 0;
          return Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    name,
                    style: GoogleFonts.getFont(
                      'DM Sans',
                      fontSize: 12,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                Text(
                  '$cals kcal',
                  style: GoogleFonts.getFont(
                    'DM Sans',
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.orange,
                  ),
                ),
              ],
            ),
          );
        }),

        const SizedBox(height: 10),

        // Action buttons
        Row(
          children: [
            Expanded(
              child: GestureDetector(
                onTap: _saving ? null : () {
                  if (_saving) return;
                  setState(() => _saving = true);
                  final result = ref.read(scanMealProvider).result;
                  if (result != null) {
                    final now = DateTime.now();
                    final dateStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
                    final id = 'nlog_${now.millisecondsSinceEpoch}';
                    final items = result['items'] as List<dynamic>? ?? [];
                    int totalProtein = 0, totalCarbs = 0, totalFat = 0, totalFiber = 0;
                    for (final item in items) {
                      if (item is Map) {
                        totalProtein += (item['protein'] as num?)?.toInt() ?? 0;
                        totalCarbs += (item['carbs'] as num?)?.toInt() ?? 0;
                        totalFat += (item['fat'] as num?)?.toInt() ?? 0;
                        totalFiber += (item['fiber'] as num?)?.toInt() ?? 0;
                      }
                    }
                    HiveService.instance.nutritionBox.put(id, {
                      'id': id,
                      'date': dateStr,
                      'meal_type': 'snacks',
                      'food_name': result['meal_name'] ?? 'Scanned Meal',
                      'total_calories': (result['total_calories'] as num?)?.toInt() ?? 0,
                      'total_protein': totalProtein,
                      'total_carbs': totalCarbs,
                      'total_fat': totalFat,
                      'total_fiber': totalFiber,
                      'created_at': now.toIso8601String(),
                      'source': 'scan_meal',
                    });
                    ref.invalidate(dailyNutritionProvider);
                  }
                  ref.read(scanMealProvider.notifier).clear();
                  if (mounted) setState(() => _saving = false);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Meal saved ✓'), duration: Duration(seconds: 1)),
                    );
                  }
                },
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
}
