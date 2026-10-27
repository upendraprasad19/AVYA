import 'package:flutter/material.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/shared/widgets/wardroom/wardroom.dart';

/// Small PRO status chip — a thin wrapper around [WardChip] so callers
/// don't need to know the Wardroom primitive exists.
///
/// The [scale] knob is preserved for source compatibility but is no longer
/// honoured — Wardroom chips have a single disciplined size. Existing
/// callsites compile unchanged.
///
/// ```dart
/// Row(children: [
///   Text('AI Coach'),
///   const SizedBox(width: 6),
///   const ProBadge(),
/// ]);
/// ```
class ProBadge extends StatelessWidget {
  /// Retained for backward compatibility; ignored visually.
  final double scale;

  const ProBadge({super.key, this.scale = 1.0});

  @override
  Widget build(BuildContext context) {
    return const WardChip(
      label: 'PRO',
      tone: WardChipTone.gold,
      leading: Icon(
        Icons.workspace_premium,
        size: 10,
        color: AppColors.accent,
      ),
    );
  }
}
