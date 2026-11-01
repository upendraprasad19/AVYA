import 'package:flutter/material.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/shared/widgets/wardroom/wardroom.dart';
import 'hydration_card.dart';

/// Opens the hydration bottom sheet (founder call 2026-11-01).
///
/// The full [HydrationCard] (water glasses, +250/+500 ml quick-add AND the urine
/// status picker) used to sit inline between the Log Food button and the day's
/// meals, pushing the logged foods off screen. It now lives behind the
/// `LOG HYDRATION` button. The card itself is unchanged: every write still goes
/// through `WaterIntakeNotifier` / `UrineColorNotifier`, so the summary ring and
/// Home read the same totals.
///
/// The urine colour picker expands inline (AnimatedSize) inside the card, so the
/// body scrolls and pads for the keyboard / safe area instead of assuming a fixed
/// height.
void showHydrationSheet(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const HydrationSheet(),
  );
}

class HydrationSheet extends StatelessWidget {
  const HydrationSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: media.size.height * 0.85),
      child: Container(
        key: const ValueKey('hydration_sheet'),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(AppRadius.card)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 14, 12, 8),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.line2,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      'LOG HYDRATION',
                      style: AppTypography.mono.copyWith(
                        color: AppColors.textPrimary,
                        letterSpacing: 2,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      key: const ValueKey('hydration_sheet_close'),
                      icon: Icon(Icons.close, color: AppColors.textDim),
                      onPressed: () => Navigator.of(context).maybePop(),
                    ),
                  ],
                ),
              ),
              const WardRule(margin: EdgeInsets.zero),
              Flexible(
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(
                    AppSpacing.screenPadding,
                    14,
                    AppSpacing.screenPadding,
                    14 + media.viewInsets.bottom,
                  ),
                  child: const HydrationCard(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
