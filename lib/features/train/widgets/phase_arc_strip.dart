import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/plan_engine_flags.dart';
import '../providers/train_provider.dart';

/// ⑥ Batch 7-A (W3.2): Phase Arc — a read-only strip showing the current phase's
/// periodization wave with THIS week highlighted. Sourced from the
/// already-materialized `week_character` via [phaseArcProvider]; renders NOTHING
/// when the kill-switch is set or there is no plan. Pure DISPLAY — no engine
/// coupling. LIVE since 2026-09-05.
///
/// ⚠ The wave vocabulary is FIVE tokens, not the four this comment used to name:
/// `baseline | overreach | peak | deload` plus `working`
/// (`deload_evaluator.dart:244`, written when a deload is lifted). The reader
/// also synthesises a sixth state, the empty string, for a malformed entry. See
/// [labelFor].
class PhaseArcStrip extends ConsumerWidget {
  const PhaseArcStrip({super.key});

  /// Raw `week_character` → display label. Unknown → the raw token upper-cased
  /// (crash-safe: a future/renamed wave still renders something sensible).
  ///
  /// `working` is the FIFTH token, written by `deload_evaluator.dart:244` when a
  /// deload is lifted. It rendered correctly before this entry existed — via the
  /// unknown-token fallback — which is exactly why it went unnoticed: it read
  /// acceptably by luck rather than by decision. Mapping it makes it deliberate.
  static const _labels = <String, String>{
    'baseline': 'BASELINE',
    'overreach': 'OVERREACH',
    'peak': 'PEAK',
    'deload': 'DELOAD',
    'working': 'WORKING',
  };

  /// Display label for one raw `week_character`, normalised ONCE.
  ///
  /// ⚠ The lookup and the fallback must share a normalisation or the fallback
  /// re-opens the hole the lookup closes: before this, the map was probed with
  /// `.toLowerCase().trim()` while the fallback used the RAW token, so `'  '`
  /// missed the map, fell through untrimmed, and `'  '.isEmpty` is FALSE — a
  /// node with a dot and no visible label. The empty string is a real state:
  /// `workout_schedule_read_service.dart:1279` synthesises it for any entry
  /// that is not a Map or whose key is null.
  static String labelFor(String rawToken) {
    final t = rawToken.toLowerCase().trim();
    return _labels[t] ?? (t.isEmpty ? '—' : t.toUpperCase());
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final arc = ref.watch(phaseArcProvider);
    if (arc == null) return const SizedBox.shrink();
    final waves = arc.waves;
    // ⑥ Batch 10 (W3.1 explainability): the deload "why" — shown ONLY on the
    // deload week (week 4), when a reason was stamped (deload feature ON). Null /
    // not-week-4 → no line → the strip is byte-identical to Batch 7-A.
    //
    // LIVE since 2026-09-06 (Unit B, OI-53 flag 4; kill-switch
    // `disable_deload_reason_line`). It shipped dark on 2026-09-05 because the
    // stamped reason can outlive the blob state it describes — a regen
    // re-stamps week 4 as `deload` while the reason still reads "Working week".
    // Unit B fixed that at the READER (diagnose `c5a8f3`): the reason is stored
    // with its outcome `week_character` and
    // `WorkoutScheduleReadService.validatedDeloadReason` returns the text ONLY
    // while that still equals week 4 of the SAME blob this strip renders — so
    // the line can never contradict the node above it.
    //
    // The flag is still checked FIRST, so the provider is not watched when the
    // kill-switch is set.
    final reason = PlanEngineFlags.deloadReasonLineEnabled &&
            arc.currentWeek == 4
        ? ref.watch(deloadReasonProvider)
        : null;

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
                    label: labelFor(waves[i]),
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
