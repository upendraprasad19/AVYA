import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import '../providers/train_provider.dart';

/// ⑥ Batch 7-A (W3.2): Phase Arc — a read-only strip showing the current phase's
/// periodization wave (baseline → overreach → peak → deload) with THIS week
/// highlighted. Sourced from the already-materialized `week_character` via
/// [phaseArcProvider]; renders NOTHING when the flag is OFF (ship-dark) or there
/// is no plan. Pure DISPLAY — no engine coupling.
class PhaseArcStrip extends ConsumerWidget {
  const PhaseArcStrip({super.key});

  /// Raw `week_character` → display label. Unknown → the raw token upper-cased
  /// (crash-safe: a future/renamed wave still renders something sensible).
  static const _labels = <String, String>{
    'baseline': 'BASELINE',
    'overreach': 'OVERREACH',
    'peak': 'PEAK',
    'deload': 'DELOAD',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final arc = ref.watch(phaseArcProvider);
    if (arc == null) return const SizedBox.shrink();
    final waves = arc.waves;
    // ⑥ Batch 10 (W3.1 explainability): the deload "why" — shown ONLY on the
    // deload week (week 4), when a reason was stamped (deload feature ON). Null /
    // not-week-4 → no line → the strip is byte-identical to Batch 7-A.
    final reason =
        arc.currentWeek == 4 ? ref.watch(deloadReasonProvider) : null;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.cardM),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'THIS PHASE',
            style: AppTypography.label
                .copyWith(letterSpacing: 1.2, color: AppColors.textDim),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              for (int i = 0; i < waves.length; i++)
                Expanded(
                  child: _node(
                    label: _labels[waves[i].toLowerCase().trim()] ??
                        waves[i].toUpperCase(),
                    isCurrent: (i + 1) == arc.currentWeek,
                    isPast: (i + 1) < arc.currentWeek,
                  ),
                ),
            ],
          ),
          if (reason != null && reason.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              reason,
              style: AppTypography.bodySm
                  .copyWith(color: AppColors.textDim, height: 1.35),
            ),
          ],
        ],
      ),
    );
  }

  Widget _node({
    required String label,
    required bool isCurrent,
    required bool isPast,
  }) {
    final Color fg = isCurrent
        ? AppColors.accent
        : (isPast ? AppColors.textDim : AppColors.textMute);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isCurrent
                ? AppColors.accent
                : (isPast ? AppColors.textDim : Colors.transparent),
            border: Border.all(
                color: isCurrent ? AppColors.accent : AppColors.textMute,
                width: 1.5),
          ),
        ),
        const SizedBox(height: 5),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.clip,
          textAlign: TextAlign.center,
          style: AppTypography.micro.copyWith(
              fontSize: 8,
              fontWeight: isCurrent ? FontWeight.w800 : FontWeight.w600,
              letterSpacing: 0.3,
              color: fg),
        ),
      ],
    );
  }
}
