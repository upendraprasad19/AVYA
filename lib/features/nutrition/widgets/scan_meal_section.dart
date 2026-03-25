import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:icanbefitter/core/constants/app_constants.dart';
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
class ScanMealSection extends ConsumerWidget {
  const ScanMealSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scanState = ref.watch(scanMealProvider);
    final remaining = ref.watch(scanMealRemainingProvider);
    final isPro = SubscriptionService.instance.isPro();
    final limit = isPro
        ? AppConstants.proScanMealPerDay
        : AppConstants.freeScanMealPerMonth;
    final used = UsageCounterService.instance
        .used(AppConstants.featureScanMealPro, isPro);
    final periodLabel = isPro ? 'today' : 'this month';

    // Soft cap warning for PRO: show at 2/3 used
    final showSoftCap = isPro && used >= 2 && remaining > 0;

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
                  '$remaining/$limit $periodLabel',
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
                    '$used of $limit scans used today',
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
            _buildError(scanState.error!, ref)
          else if (scanState.result != null)
            _buildResult(context, scanState.result!, ref)
          else
            _buildScanButton(context, ref, remaining),
        ],
      ),
    );
  }

  Widget _buildScanButton(
      BuildContext context, WidgetRef ref, int remaining) {
    return SizedBox(
      width: double.infinity,
      child: GestureDetector(
        onTap: () => _handleScan(context, ref, remaining),
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

  Future<void> _handleScan(BuildContext context, WidgetRef ref, int remaining) async {
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

    final picker = ImagePicker();
    final image = await picker.pickImage(source: ImageSource.camera);
    if (image == null) return;

    final imageBytes = await image.readAsBytes();
    final isPro = SubscriptionService.instance.isPro();
    ref.read(scanMealProvider.notifier).scanImage(imageBytes);
    await UsageCounterService.instance.increment(AppConstants.featureScanMealPro, isPro);
  }

  Widget _buildError(String error, WidgetRef ref) {
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

  Widget _buildResult(
      BuildContext context, Map<String, dynamic> result, WidgetRef ref) {
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
                onTap: () {
                  // TODO: Save scanned result to nutrition log
                  ref.read(scanMealProvider.notifier).clear();
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
