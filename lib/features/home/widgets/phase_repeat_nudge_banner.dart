import 'package:flutter/material.dart';

import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/theme/typography.dart';

/// ⑧ 3-a2 (W2.5): non-shaming Home banner shown after a low-adherence phase
/// advance REPEATED last phase's plan (at detrained loads) instead of a fresh
/// pick. Dismissible (X) — the flag is cleared only on the explicit dismiss tap
/// (via `phaseRepeatNudgeProvider.dismiss()`), NEVER in build, so it survives
/// Home rebuilds until acted on. Navy framing: "run the drill again", never
/// "you failed". Ship-dark: only ever surfaces when the writer set the flag,
/// which requires `enable_adherence_gate` ON.
class PhaseRepeatNudgeBanner extends StatelessWidget {
  final VoidCallback onDismiss;

  const PhaseRepeatNudgeBanner({super.key, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(
          AppSpacing.screenPadding, 0, AppSpacing.screenPadding, 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.cardM),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          const Icon(Icons.replay_rounded, size: 20, color: AppColors.accent),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Same drills, fresh start. Nail this phase and we’ll step '
              'it up next time.',
              style: AppTypography.body.copyWith(
                  fontSize: 13, color: AppColors.textDim, height: 1.35),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: onDismiss,
            behavior: HitTestBehavior.opaque,
            child: const Padding(
              padding: EdgeInsets.all(4),
              child:
                  Icon(Icons.close, size: 18, color: AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}
