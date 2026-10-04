import 'package:flutter/material.dart';

import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/theme/typography.dart';

/// "PATTERNS I'VE NOTICED" block on the AI Coach screen — matches the
/// Wardroom handoff spec (`design_handoff_wardroom/src/screens/coach.
/// jsx` lines 141–164): mono eyebrow, three stacked cards each with
/// a 36-px circle showing confidence % (mono Fraunces numeric) on
/// the left and a DM Sans body observation on the right.
///
/// Data source: static defaults for now. Reading from `coaching_notes`
/// (in coachBox) would require a schema for confidence + observation
/// structuring that the notes pipeline doesn't emit today — notes are
/// free-form prose. Wiring that path is out of AG.2 scope; when the
/// `rolling-context` Edge Function starts emitting structured
/// patterns, swap the static list for a provider read.
class CoachPatternsCard extends StatelessWidget {
  const CoachPatternsCard({super.key});

  @override
  Widget build(BuildContext context) {
    final patterns = _Pattern.defaults;

    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            "PATTERNS I'VE NOTICED",
            style: AppTypography.monoXs.copyWith(
              color: AppColors.textMute,
              letterSpacing: 2,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < patterns.length; i++) ...[
            _PatternRow(pattern: patterns[i]),
            if (i < patterns.length - 1) const SizedBox(height: 6),
          ],
        ],
      ),
    );
  }
}

class _PatternRow extends StatelessWidget {
  const _PatternRow({required this.pattern});
  final _Pattern pattern;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(color: AppColors.line2),
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: AppColors.accent.withValues(alpha: 0.40),
                width: 1.5,
              ),
            ),
            child: Text(
              '${pattern.confidence}',
              style: AppTypography.mono.copyWith(
                fontSize: 9,
                color: AppColors.accent,
                fontWeight: FontWeight.w700,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              pattern.observation,
              style: AppTypography.body.copyWith(
                fontSize: 12,
                color: AppColors.textPrimary,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Pattern {
  const _Pattern({required this.confidence, required this.observation});
  final int confidence;
  final String observation;

  static const defaults = <_Pattern>[
    _Pattern(
      confidence: 94,
      observation:
          'You lift heaviest on Tuesdays — recovery is cleanest.',
    ),
    _Pattern(
      confidence: 88,
      observation:
          'Under 7h sleep → PR attempts fail 72% of the time.',
    ),
    _Pattern(
      confidence: 81,
      observation:
          'Days with breakfast logged have +12% better afternoon energy.',
    ),
  ];
}
