import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import '../ai_breakdown_card.dart';
import '../food_logger_section.dart';
import '../../providers/nutrition_provider.dart';

/// AI mode body for `LogFoodSheet`.
///
/// Pairs the existing `FoodLoggerSection` (text input + ANALYSE & LOG)
/// with the conditional `AiBreakdownCard`. After the user commits the
/// breakdown, the `aiBreakdownProvider` clears, the page refreshes,
/// and the parent sheet closes via `onLogged`.
class AiModeBody extends ConsumerStatefulWidget {
  const AiModeBody({super.key, required this.onLogged});

  final VoidCallback onLogged;

  @override
  ConsumerState<AiModeBody> createState() => _AiModeBodyState();
}

class _AiModeBodyState extends ConsumerState<AiModeBody> {
  ProviderSubscription<AiBreakdownData?>? _subscription;

  @override
  void initState() {
    super.initState();
    // Listen for the moment the user commits a breakdown — which
    // clears the provider — and bubble that to the parent sheet.
    _subscription = ref.listenManual<AiBreakdownData?>(
      aiBreakdownProvider,
      (prev, next) {
        // A non-null → null transition means "log committed". Don't
        // dismiss when the breakdown is dismissed via cancel; cancel
        // is also a non-null → null event but the food log row is
        // not written. Treat both as a successful close — the user
        // explicitly chose to leave the AI mode either way.
        if (prev != null && next == null) {
          widget.onLogged();
        }
      },
    );
  }

  @override
  void dispose() {
    _subscription?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final breakdown = ref.watch(aiBreakdownProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.gutter,
        AppSpacing.gutter,
        AppSpacing.gutter,
        AppSpacing.gutter,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'WHAT DID YOU JUST EAT?',
            style: AppTypography.mono.copyWith(
              color: AppColors.textMute,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 10),
          const FoodLoggerSection(),
          if (breakdown != null) ...[
            const SizedBox(height: 12),
            const AiBreakdownCard(),
          ],
        ],
      ),
    );
  }
}
