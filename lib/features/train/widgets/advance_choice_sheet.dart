// ⑧ 8-B / UNIT 3-b — the graduation "repeat vs advance" choice sheet + the pure
// gate helper. Shown from graduation `_onPro` when a low-adherence PRO taps
// "generate next phase" (ship-dark, `enable_adherence_gate`). Non-shaming Navy
// framing: two FORWARD options, never "you failed / you missed / low adherence".

import 'package:flutter/material.dart';

import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/shared/widgets/wardroom/wardroom.dart';

/// The user's choice at a low-adherence phase advance. The phase ALWAYS advances
/// (F3 reframe); this only decides what the next phase CONTAINS.
enum AdvanceChoice { repeat, advance }

/// PURE gate: offer the choice when the just-finished phase's completion is low.
/// The FLAG check lives at the CALLSITE (`adherenceGateEnabled &&
/// shouldOfferAdvanceChoice(...)`) so the ~90-Hive-read `currentPhaseCompletionRate()`
/// is never evaluated when the flag is OFF — Dart evaluates args eagerly, so the
/// outer `&&` must short-circuit the whole call. Mirrors `pro_phase_advance.dart`.
bool shouldOfferAdvanceChoice({
  required double completionRate,
  required double threshold,
}) =>
    completionRate < threshold;

/// Shows the two-option sheet. Returns the chosen [AdvanceChoice], or `null` on
/// barrier-tap / back / swipe — the caller treats `null` as [AdvanceChoice.advance]
/// so dismiss NEVER blocks the advance.
Future<AdvanceChoice?> showAdvanceChoiceSheet(BuildContext context) {
  return showModalBottomSheet<AdvanceChoice>(
    context: context,
    backgroundColor: AppColors.card,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (_) => const _AdvanceChoiceSheet(),
  );
}

class _AdvanceChoiceSheet extends StatelessWidget {
  const _AdvanceChoiceSheet();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'HOW DO YOU WANT TO RUN THIS ONE?',
              style: AppTypography.mono
                  .copyWith(color: AppColors.accent, letterSpacing: 2),
            ),
            const SizedBox(height: 6),
            Text(
              'Run the same drills again to lock them in, or take on fresh '
              'orders. Either way, the next phase is yours.',
              style: AppTypography.monoXs
                  .copyWith(color: AppColors.textDim, height: 1.4),
            ),
            const SizedBox(height: 22),
            WardButton(
              label: 'RUN THE SAME DRILLS AGAIN',
              variant: WardButtonVariant.primary,
              onPressed: () => Navigator.of(context).pop(AdvanceChoice.repeat),
            ),
            const SizedBox(height: 8),
            WardButton(
              label: 'GIVE ME FRESH ORDERS',
              variant: WardButtonVariant.ghost,
              onPressed: () => Navigator.of(context).pop(AdvanceChoice.advance),
            ),
          ],
        ),
      ),
    );
  }
}
