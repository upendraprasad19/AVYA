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

/// Cart auditor: upload grocery screenshot -> Gemini Vision analysis.
///
/// FREE: 1 scan/month. PRO: 3 scans/day with soft cap warning.
class CartAuditorSection extends ConsumerWidget {
  const CartAuditorSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(cartAuditorProvider);
    final remaining = ref.watch(cartAuditorRemainingProvider);
    final isPro = SubscriptionService.instance.isPro();
    final limit = isPro
        ? AppConstants.proCartAuditorPerDay
        : AppConstants.freeCartAuditorPerDay;
    final used = UsageCounterService.instance
        .used(AppConstants.featureCartAuditorPro, isPro);
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
          // Header
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: AppColors.green.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.shopping_cart_outlined,
                    color: AppColors.green, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Cart Auditor',
                      style: GoogleFonts.getFont(
                        'DM Sans',
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    Text(
                      'Upload grocery screenshot for macro analysis',
                      style: GoogleFonts.getFont(
                        'DM Sans',
                        fontSize: 10,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: remaining > 0
                      ? AppColors.green.withValues(alpha: 0.08)
                      : AppColors.red.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(AppRadius.badge),
                ),
                child: Text(
                  '$remaining/$limit $periodLabel',
                  style: GoogleFonts.getFont(
                    'DM Sans',
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: remaining > 0 ? AppColors.green : AppColors.red,
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
                    '$used of $limit audits used today',
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

          if (state.isAnalysing)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: CircularProgressIndicator(
                  color: AppColors.green,
                  strokeWidth: 2,
                ),
              ),
            )
          else if (state.error != null)
            _buildError(state.error!, ref)
          else if (state.result != null)
            _buildResult(state.result!, ref)
          else
            _buildUploadButton(context, ref, remaining),
        ],
      ),
    );
  }

  Widget _buildUploadButton(
      BuildContext context, WidgetRef ref, int remaining) {
    return SizedBox(
      width: double.infinity,
      child: GestureDetector(
        onTap: () => _handleUpload(context, ref, remaining),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.green.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(AppRadius.row),
            border:
                Border.all(color: AppColors.green.withValues(alpha: 0.2)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.upload_file, color: AppColors.green, size: 18),
              const SizedBox(width: 8),
              Text(
                'Upload Grocery Screenshot',
                style: GoogleFonts.getFont(
                  'DM Sans',
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.green,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleUpload(BuildContext context, WidgetRef ref, int remaining) async {
    if (remaining <= 0) {
      SubscriptionService.instance.gate(
        AppConstants.featureCartAuditorPro,
        onPro: () {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Daily cart auditor limit reached. Try again tomorrow.',
                style: GoogleFonts.getFont('DM Sans', fontSize: 13),
              ),
              backgroundColor: AppColors.card,
            ),
          );
        },
        onFree: () =>
            showPaywallSheet(context, feature: 'Cart Auditor'),
      );
      return;
    }

    final picker = ImagePicker();
    final image = await picker.pickImage(source: ImageSource.gallery);
    if (image == null) return;

    final imageBytes = await image.readAsBytes();
    // Quota increment moved to CartAuditorNotifier.analyseCart() success path
    // so failures don't consume a daily attempt.
    ref.read(cartAuditorProvider.notifier).analyseCart(imageBytes);
  }

  Widget _buildError(String error, WidgetRef ref) {
    return Column(
      children: [
        Text(
          error,
          style: GoogleFonts.getFont('DM Sans', fontSize: 12, color: AppColors.red),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: () => ref.read(cartAuditorProvider.notifier).clear(),
          child: Text(
            'Try Again',
            style: GoogleFonts.getFont(
              'DM Sans',
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.green,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildResult(Map<String, dynamic> result, WidgetRef ref) {
    final items = (result['items'] as List<dynamic>?) ?? [];
    final swaps = (result['swap_suggestions'] as List<dynamic>?) ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Cart Analysis',
          style: GoogleFonts.getFont(
            'DM Sans',
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 8),

        // Items
        ...items.map((item) {
          final name = item['name'] as String? ?? 'Unknown';
          final verdict = item['verdict'] as String? ?? '';
          final color = verdict == 'good' ? AppColors.green : AppColors.orange;
          return Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              children: [
                Icon(
                  verdict == 'good'
                      ? Icons.check_circle
                      : Icons.warning_amber_rounded,
                  size: 14,
                  color: color,
                ),
                const SizedBox(width: 6),
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
              ],
            ),
          );
        }),

        // Swap suggestions
        if (swaps.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            'SWAP SUGGESTIONS',
            style: GoogleFonts.getFont(
              'DM Sans',
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.0,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          ...swaps.map((swap) {
            final from = swap['from'] as String? ?? '';
            final to = swap['to'] as String? ?? '';
            final reason = swap['reason'] as String? ?? '';
            return Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '$from \u2192 $to ($reason)',
                style: GoogleFonts.getFont(
                  'DM Sans',
                  fontSize: 11,
                  color: AppColors.accent,
                ),
              ),
            );
          }),
        ],

        const SizedBox(height: 10),

        // Dismiss
        SizedBox(
          width: double.infinity,
          child: GestureDetector(
            onTap: () => ref.read(cartAuditorProvider.notifier).clear(),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 9),
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.border),
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
              alignment: Alignment.center,
              child: Text(
                'Done',
                style: GoogleFonts.getFont(
                  'DM Sans',
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
