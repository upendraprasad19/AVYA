// lib/features/nutrition/widgets/diet_serving_view_toggle.dart
//
// OI-517 (docs/plans/diet-grams-toggle.md sections 3 and 13): the Portions /
// Grams switch at the right end of the BMR / TDEE / TARGET card. A stacked
// two-line control (PORTIONS over GRAMS, the active line filled); the WHOLE
// control is one tap target of the card's inner height that flips the view,
// and ONE Semantics node announces it (button, "Serving view", value).
// Does not reuse WardUnitToggle: that one is horizontal, ~24 dp segments and
// 134 dp wide with these labels.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/features/profile/providers/profile_provider.dart';
import '../providers/diet_serving_view_provider.dart';
import '../services/diet_serving_view_actions.dart';
import '../services/diet_serving_label.dart';

class DietServingViewToggle extends ConsumerWidget {
  const DietServingViewToggle({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(dietServingViewProvider);
    final grams = view == DietServingView.grams;
    final next = grams ? DietServingView.portions : DietServingView.grams;
    return Semantics(
      container: true,
      button: true,
      label: 'Serving view',
      value: grams ? 'Grams' : 'Portions',
      onTap: () => _flip(ref, next),
      child: ExcludeSemantics(
        child: GestureDetector(
          key: const ValueKey('diet_serving_view_toggle'),
          behavior: HitTestBehavior.opaque,
          onTap: () => _flip(ref, next),
          // 3 dp of tappable padding above and below the drawn control: the
          // whole thing is one target as tall as the card's inner height.
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Container(
              padding: const EdgeInsets.all(1),
              decoration: BoxDecoration(
                color: AppColors.bgRaise,
                border: Border.all(color: AppColors.line2),
                borderRadius: BorderRadius.circular(AppRadius.sharp),
              ),
              // IntrinsicWidth + stretch: both segments take the width of the
              // longer label, so the gold fill of the active one always spans
              // the whole control (polish, 2026-11-18).
              child: IntrinsicWidth(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _line(
                      'PORTIONS',
                      !grams,
                      const ValueKey('diet_serving_view_portions'),
                    ),
                    const SizedBox(height: 2),
                    _line(
                      'GRAMS',
                      grams,
                      const ValueKey('diet_serving_view_grams'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  static void _flip(WidgetRef ref, DietServingView next) {
    // `patchProfile` records the failure to telemetry and rethrows; a tap has
    // no caller to catch it, so it must not surface as an uncaught zone error
    // (the switch simply does not move).
    unawaited(
      setDietServingView(
        ref.read(userProfileProvider.notifier),
        next,
      ).catchError((Object _) {}),
    );
  }

  // Each option is its own chip: the active one is filled gold, the other a
  // visible outlined chip (not bare text), so both read as choices.
  static Widget _line(String label, bool selected, Key key) => Container(
    key: key,
    alignment: Alignment.center,
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: selected ? AppColors.accent : Colors.transparent,
      border: Border.all(color: selected ? AppColors.accent : AppColors.line2),
      borderRadius: BorderRadius.circular(AppRadius.sharp),
    ),
    child: Text(
      label,
      maxLines: 1,
      style: AppTypography.monoXs.copyWith(
        fontSize: 9,
        height: 1.0,
        letterSpacing: 0.5,
        fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
        color: selected ? AppColors.bgDeep : AppColors.textDim,
      ),
    ),
  );
}
