import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:icanbefitter/core/services/service_providers.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/features/profile/providers/profile_provider.dart';

/// Compact 3-phase roadmap card shown on Train while the user is holding —
/// "you are still on Phase I; II and III are what PRO buys" in one glance
/// (locked mockup `docs/design/holdweek_train_mockup.html`).
///
/// **Display-only.** No tap target, so no `subscription.gate()` is needed — the
/// PRO lock here is a label, not an entry point. The real upgrade doors are the
/// PaywallSheet CTAs on `plan_expired_card` / `phase_unlock_card`, and the full
/// `/train/roadmap` screen is one tap away via the existing pill above.
///
/// Phase numbering is PINNED to the current phase and its next two — holds do
/// NOT advance it, and the 12-week roadmap never drifts (founder decision:
/// "PHASE II stays pinned at W5-W8"). Nothing here reads `getProgramWeek()`,
/// which mis-reports for a holder.
class HoldRoadmapStrip extends ConsumerWidget {
  const HoldRoadmapStrip({super.key, required this.currentPhase});

  final int currentPhase;

  static const _romans = ['I', 'II', 'III', 'IV', 'V', 'VI', 'VII', 'VIII', //
    'IX', 'X', 'XI', 'XII'];

  static String _roman(int phase) =>
      (phase >= 1 && phase <= _romans.length) ? _romans[phase - 1] : '$phase';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isPro = ref.watch(subscriptionInfoProvider).isPro;
    final readService = ref.read(workoutScheduleReadServiceProvider);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.screenPadding),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.cardM),
        border: Border.all(color: AppColors.line2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '12-WEEK ROADMAP',
                style: AppTypography.monoXs.copyWith(
                  color: AppColors.textMute,
                  letterSpacing: 1.6,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Text(
                'PHASE ${_roman(currentPhase)} · HOLDING',
                style: AppTypography.monoXs.copyWith(
                  color: AppColors.accent,
                  letterSpacing: 1,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              for (var offset = 0; offset < 3; offset++) ...[
                if (offset > 0) const SizedBox(width: 8),
                Expanded(
                  child: _PhaseBox(
                    name: readService.phaseName(currentPhase + offset),
                    roman: _roman(currentPhase + offset),
                    isActive: offset == 0,
                    isLocked: offset > 0 && !isPro,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _PhaseBox extends StatelessWidget {
  const _PhaseBox({
    required this.name,
    required this.roman,
    required this.isActive,
    required this.isLocked,
  });

  final String name;
  final String roman;
  final bool isActive;
  final bool isLocked;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
      decoration: BoxDecoration(
        color: isActive ? AppColors.cardHi : AppColors.input,
        borderRadius: BorderRadius.circular(AppRadius.cardS),
        border: Border.all(
          color: isActive ? AppColors.accent : AppColors.line2,
          width: isActive ? 1.5 : 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            roman,
            style: AppTypography.monoXs.copyWith(
              fontSize: 15,
              fontWeight: FontWeight.w900,
              color: isActive ? AppColors.accent : AppColors.textGhost,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.body.copyWith(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: isActive ? AppColors.textPrimary : AppColors.textMute,
            ),
          ),
          const SizedBox(height: 1),
          Row(
            children: [
              if (isLocked) ...[
                Icon(Icons.lock, size: 9, color: AppColors.textMute),
                const SizedBox(width: 3),
              ],
              Text(
                isActive
                    ? 'Active'
                    : isLocked
                        ? 'PRO'
                        : 'Next',
                style: AppTypography.monoXs.copyWith(
                  fontSize: 9,
                  letterSpacing: 0.5,
                  color: isActive ? AppColors.textDim : AppColors.textMute,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
