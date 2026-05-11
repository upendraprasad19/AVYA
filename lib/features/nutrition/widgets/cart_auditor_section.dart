import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:icanbefitter/core/constants/app_constants.dart';
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

/// Cart auditor: upload grocery screenshot -> Gemini Vision analysis.
///
/// FREE: 1 scan/month. PRO: 3 scans/day with soft cap warning.
class CartAuditorSection extends ConsumerWidget {
  const CartAuditorSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(cartAuditorProvider);
    final remaining = ref.watch(cartAuditorRemainingProvider);
    final isPro = ref.watch(subscriptionInfoProvider).isPro;
    final limit = isPro
        ? AppConstants.proCartAuditorPerDay
        : AppConstants.freeCartAuditorPerDay;
    final used = UsageCounterService.instance
        .used(AppConstants.featureCartAuditorPro, isPro);

    // Soft cap warning for PRO: show at 7/10 used
    final showSoftCap = isPro && used >= 7 && remaining > 0;

    return WardCard(
      padding: const EdgeInsets.all(AppSpacing.cardPadding),
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
                  color: AppColors.ok.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadius.sharp),
                ),
                child: const Icon(Icons.shopping_cart_outlined,
                    color: AppColors.ok, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'CART AUDITOR',
                      style: AppTypography.mono.copyWith(
                        color: AppColors.textMute,
                        letterSpacing: 2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Upload grocery screenshot',
                      style: AppTypography.bodySm.copyWith(
                        color: AppColors.textDim,
                      ),
                    ),
                  ],
                ),
              ),
              WardChip(
                label: '$remaining/$limit TODAY',
                tone: remaining > 0 ? WardChipTone.ok : WardChipTone.bad,
              ),
            ],
          ),

          // Soft cap warning
          if (showSoftCap) ...[
            const SizedBox(height: 10),
            WardChip(
              label: '$used OF $limit AUDITS USED TODAY',
              tone: WardChipTone.warn,
            ),
          ],

          const SizedBox(height: 12),

          if (state.isAnalysing)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: CircularProgressIndicator(
                  color: AppColors.ok,
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
            color: AppColors.ok.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(AppRadius.sharp),
            border:
                Border.all(color: AppColors.ok.withValues(alpha: 0.35), width: 2),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.upload_file, color: AppColors.ok, size: 18),
              const SizedBox(width: 8),
              Text(
                'UPLOAD SCREENSHOT',
                style: AppTypography.mono.copyWith(
                  color: AppColors.ok,
                  letterSpacing: 2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleUpload(
      BuildContext context, WidgetRef ref, int remaining) async {
    if (remaining <= 0) {
      SubscriptionService.instance.gate(
        AppConstants.featureCartAuditorPro,
        onPro: () {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Daily cart auditor limit reached. Try again tomorrow.',
                style: AppTypography.body,
              ),
              backgroundColor: AppColors.card,
            ),
          );
        },
        onFree: () => showPaywallSheet(context, feature: 'Cart Auditor'),
      );
      return;
    }

    final picker = ImagePicker();
    final image = await picker.pickImage(source: ImageSource.gallery);
    if (image == null) return;

    final imageBytes = await image.readAsBytes();
    // Quota increment moved to CartAuditorNotifier.analyseCart() success path
    // so failures don't consume a daily attempt.
    unawaited(ref.read(cartAuditorProvider.notifier).analyseCart(imageBytes));
  }

  Widget _buildError(String error, WidgetRef ref) {
    return Column(
      children: [
        Text(
          error,
          style: AppTypography.bodySm.copyWith(color: AppColors.bad),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: () => ref.read(cartAuditorProvider.notifier).clear(),
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

  Widget _buildResult(Map<String, dynamic> result, WidgetRef ref) {
    final items = (result['items'] as List<dynamic>?) ?? [];
    final swaps = (result['swap_suggestions'] as List<dynamic>?) ?? [];
    final score = (result['health_score'] as num?)?.toInt();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'CART ANALYSIS',
                style: AppTypography.mono.copyWith(
                  color: AppColors.textMute,
                  letterSpacing: 2,
                ),
              ),
            ),
            if (score != null) ...[
              WardRing(
                pct: (score / 100).clamp(0.0, 1.0),
                size: 56,
                stroke: 4,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '$score',
                      style: AppTypography.h3.copyWith(
                        color: AppColors.accent,
                      ),
                    ),
                    Text(
                      '/100',
                      style: AppTypography.monoXs.copyWith(
                        color: AppColors.textMute,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 10),
        const WardRule(margin: EdgeInsets.zero),
        const SizedBox(height: 10),

        // Items
        ...items.map((raw) {
          final item = raw as Map<String, dynamic>;
          final name = item['name'] as String? ?? 'Unknown';
          final verdict = item['verdict'] as String? ?? '';
          final color = verdict == 'good' ? AppColors.ok : AppColors.warn;
          return Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                Icon(
                  verdict == 'good'
                      ? Icons.check_circle
                      : Icons.warning_amber_rounded,
                  size: 14,
                  color: color,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    name,
                    style: AppTypography.body,
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
            style: AppTypography.mono.copyWith(
              color: AppColors.textMute,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 6),
          ...swaps.map((raw) {
            final swap = raw as Map<String, dynamic>;
            final from = swap['from'] as String? ?? '';
            final to = swap['to'] as String? ?? '';
            final reason = swap['reason'] as String? ?? '';
            return Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '$from \u2192 $to ($reason)',
                style: AppTypography.bodySm.copyWith(
                  color: AppColors.accent,
                ),
              ),
            );
          }),
        ],

        const SizedBox(height: 12),

        // Dismiss
        SizedBox(
          width: double.infinity,
          child: GestureDetector(
            onTap: () => ref.read(cartAuditorProvider.notifier).clear(),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.line2),
                borderRadius: BorderRadius.circular(AppRadius.sharp),
              ),
              alignment: Alignment.center,
              child: Text(
                'DONE',
                style: AppTypography.mono.copyWith(
                  color: AppColors.textDim,
                  letterSpacing: 2,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
