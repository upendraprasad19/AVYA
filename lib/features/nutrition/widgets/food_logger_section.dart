import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:icanbefitter/core/constants/app_constants.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/services/subscription_service.dart';
import 'package:icanbefitter/core/services/usage_counter_service.dart';
import 'package:icanbefitter/shared/widgets/paywall_sheet.dart';
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
                style: GoogleFonts.getFont('DM Sans', fontSize: 13),
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

    // Increment usage counter after successful analysis
    await usage.increment(AppConstants.featureAiTextLogPro, isPro);

    ref.read(aiAnalysingProvider.notifier).set(false);
    _controller.clear();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final isAnalysing = ref.watch(aiAnalysingProvider);
    final canAnalyse = _controller.text.trim().length >= 3 && !isAnalysing;
    final remaining = ref.watch(aiTextLogRemainingProvider);
    final isPro = SubscriptionService.instance.isPro();
    final limit = AppConstants.freeAiTextLogsPerDay;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.cardM),
        border: Border.all(color: AppColors.border),
      ),
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
                borderRadius: BorderRadius.circular(AppRadius.row),
                border: Border.all(
                  color: _isFocused
                      ? AppColors.accent.withValues(alpha: 0.45)
                      : AppColors.border,
                  width: 1.5,
                ),
              ),
              child: Row(
                children: [
                  // AI spark icon
                  Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: AppColors.accentTint,
                      borderRadius: BorderRadius.circular(7),
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
                      style: GoogleFonts.getFont(
                        'DM Sans',
                        fontSize: 13,
                        color: AppColors.textPrimary,
                      ),
                      decoration: InputDecoration(
                        hintText:
                            'Type what you ate (e.g. 2 rotis with dal)...',
                        hintStyle: GoogleFonts.getFont(
                          'DM Sans',
                          fontSize: 13,
                          color: AppColors.textSecondary,
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
          const SizedBox(height: 8),

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
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      decoration: BoxDecoration(
                        color: AppColors.accent,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      alignment: Alignment.center,
                      child: isAnalysing
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.black,
                              ),
                            )
                          : Text(
                              '\u2728 Analyse & Log',
                              style: GoogleFonts.getFont(
                                'DM Sans',
                                fontSize: 13,
                                fontWeight: FontWeight.w900,
                                color: Colors.black,
                              ),
                            ),
                    ),
                  ),
                ),
              ),
              if (!isPro) ...[
                const SizedBox(width: 8),
                // Usage counter badge (free users only — PRO is unlimited)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
                  decoration: BoxDecoration(
                    color: remaining > 0
                        ? AppColors.accent.withValues(alpha: 0.08)
                        : AppColors.red.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: remaining > 0
                          ? AppColors.accent.withValues(alpha: 0.2)
                          : AppColors.red.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Text(
                    '${limit - remaining}/$limit used',
                    style: GoogleFonts.getFont(
                      'DM Sans',
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: remaining > 0 ? AppColors.accent : AppColors.red,
                    ),
                  ),
                ),
              ],
            ],
          ),

          // Usage label (free users only)
          if (!isPro)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Align(
                alignment: Alignment.centerRight,
                child: Text(
                  '$remaining log${remaining == 1 ? '' : 's'} left today',
                  style: GoogleFonts.getFont(
                    'DM Sans',
                    fontSize: 9,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
