import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/features/auth/providers/auth_invalidation_provider.dart';

import '../providers/measurement_flag_provider.dart';
import 'measurements_card.dart';

/// Puts the "Body measurements" card above a screen's body (L2b Landing C, E3).
///
/// The frame OWNS the flag check and the composition, so the host adds one line
/// and an OFF build creates no measurements provider: with the flag OFF it
/// returns [child] itself (the identical widget instance).
///
/// ON, the card is pinned above [child] and capped at half the body, always
/// leaving the list [kMinListHeight] dp: `cap = min(0.5 * available, available
/// - kMinListHeight)`. Below [kMinHostHeightForCard] the card is not shown, and
/// neither is its margin in the account-swap window (the token is `'<anon>'`:
/// the card draws nothing then, so the frame must not leave a blank band). The
/// shape is the same in every state (a `Column` whose FIRST child changes and
/// whose second is `Expanded(child)`), so the child's elements and scroll
/// offset survive the keyboard opening and closing behind the sheet. An
/// unbounded host (it never occurs on the real screen) gets the child alone,
/// which keeps this total.
class MeasurementsCardFrame extends ConsumerWidget {
  const MeasurementsCardFrame({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(measurementsEnabledProvider)) return child;
    final anonymous = ref.watch(authUserIdTokenProvider) == '<anon>';
    return LayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.maxHeight;
        if (!available.isFinite) return child;
        final show = !anonymous && available >= kMinHostHeightForCard;
        final cap = math.min(0.5 * available, available - kMinListHeight);
        return Column(
          children: [
            show
                ? ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: cap),
                    child: const Padding(
                      padding: EdgeInsets.fromLTRB(
                        AppSpacing.screenPadding,
                        kCardMarginTop,
                        AppSpacing.screenPadding,
                        kCardMarginBottom,
                      ),
                      child: SizedBox(
                        width: double.infinity,
                        child: MeasurementsCard(),
                      ),
                    ),
                  )
                : const SizedBox.shrink(),
            Expanded(child: child),
          ],
        );
      },
    );
  }
}
