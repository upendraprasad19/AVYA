import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:icanbefitter/core/constants/app_constants.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/core/services/subscription_service.dart';
import 'package:icanbefitter/core/services/usage_counter_service.dart';
import 'package:icanbefitter/shared/widgets/paywall_sheet.dart';
import 'package:icanbefitter/shared/widgets/wardroom/wardroom.dart';
import 'package:icanbefitter/features/profile/providers/profile_provider.dart';
import '../providers/nutrition_provider.dart';

/// Food logger input field with AI analysis button and usage counter.
class FoodLoggerSection extends ConsumerStatefulWidget {
  const FoodLoggerSection({super.key});

  @override
  ConsumerState<FoodLoggerSection> createState() => _FoodLoggerSectionState();
}

class _FoodLoggerSectionState extends ConsumerState<FoodLoggerSection> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() {
      setState(() => _isFocused = _focusNode.hasFocus);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _analyse() async {
    final text = _controller.text.trim();
    if (text.length < 3) return;

    final isPro = SubscriptionService.instance.isPro();
    final usage = UsageCounterService.instance;

    // Check usage limit
    if (!usage.canUse(AppConstants.featureAiTextLogPro, isPro)) {
      if (!mounted) return;
      // Free user exhausted daily limit -> show paywall
      SubscriptionService.instance.gate(
        AppConstants.featureAiTextLogPro,
        onPro: () {
          // PRO user exhausted daily limit -> inform them
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Daily AI text log limit reached. Try again tomorrow.',
                style: AppTypography.body,
              ),
              backgroundColor: AppColors.card,
            ),
          );
        },
        onFree: () => showPaywallSheet(context, feature: 'AI Food Analysis'),
      );
      return;
    }

    ref.read(aiAnalysingProvider.notifier).set(true);
    await ref.read(aiBreakdownProvider.notifier).analyse(text);

    // Test #11 M1: increment counter HERE — at the API-call site — not at
    // NutritionWriteService.logMeal (the save site). The Edge Function call
    // fires inside analyse(); whether the user taps SAVE MEAL or dismisses
    // is irrelevant — the server already counted the quota. Client counter
    // must agree so the UI "X remaining" display stays in sync.
    // Reuse `isPro` already resolved at top of _analyse (line ~48).
    unawaited(
      UsageCounterService.instance.increment(
        AppConstants.featureAiTextLogPro,
        isPro,
      ),
    );

    ref.read(aiAnalysingProvider.notifier).set(false);
    _controller.clear();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final isAnalysing = ref.watch(aiAnalysingProvider);
    final canAnalyse = _controller.text.trim().length >= 3 && !isAnalysing;
    final remaining = ref.watch(aiTextLogRemainingProvider);
    // Provider watch (not direct service call) so this tile rebuilds
    // immediately when Razorpay success invalidates subscriptionInfoProvider.
    final isPro = ref.watch(subscriptionInfoProvider).isPro;
    final limit = AppConstants.freeAiTextLogsPerDay;

    return WardCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          // Input field
          GestureDetector(
            onTap: () => _focusNode.requestFocus(),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              decoration: BoxDecoration(
                color: AppColors.input,
                borderRadius: BorderRadius.circular(AppRadius.sharp),
                border: Border.all(
                  color: _isFocused
                      ? AppColors.accent.withValues(alpha: 0.45)
                      : AppColors.line2,
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  // AI spark icon
                  Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: AppColors.accentSoft,
                      borderRadius: BorderRadius.circular(AppRadius.sharp),
                    ),
                    child: const Icon(
                      Icons.auto_awesome,
                      size: 13,
                      color: AppColors.accent,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      focusNode: _focusNode,
                      onChanged: (_) => setState(() {}),
                      onSubmitted: (_) => _analyse(),
                      style: AppTypography.body,
                      decoration: InputDecoration(
                        hintText:
                            'Type what you ate (e.g. 2 rotis with dal)...',
                        hintStyle: AppTypography.body.copyWith(
                          color: AppColors.textDim,
                        ),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.stackS),

          // Analyse button + usage counter
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: canAnalyse ? _analyse : null,
                  child: AnimatedOpacity(
                    opacity: canAnalyse ? 1.0 : 0.35,
                    duration: const Duration(milliseconds: 200),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: AppColors.accent,
                        borderRadius:
                            BorderRadius.circular(AppRadius.sharp),
                      ),
                      alignment: Alignment.center,
                      child: isAnalysing
                          ? SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.bgDeep,
                              ),
                            )
                          : Text(
                              'ANALYSE & LOG',
                              style: AppTypography.mono.copyWith(
                                color: AppColors.bgDeep,
                                letterSpacing: 2,
                              ),
                            ),
                    ),
                  ),
                ),
              ),
              if (!isPro) ...[
                const SizedBox(width: 8),
                // Usage counter chip (free users only — PRO is unlimited)
                WardChip(
                  label: '${limit - remaining}/$limit USED',
                  tone: remaining > 0
                      ? WardChipTone.gold
                      : WardChipTone.bad,
                ),
              ],
            ],
          ),

          // Usage label (free users only)
          if (!isPro)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Align(
                alignment: Alignment.centerRight,
                child: Text(
                  '$remaining log${remaining == 1 ? '' : 's'} left today'
                      .toUpperCase(),
                  style: AppTypography.monoXs.copyWith(
                    color: AppColors.textMute,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
