import 'package:flutter/material.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/typography.dart';

/// Section header label — Mono caps eyebrow in the Wardroom voice.
class SectionHeader extends StatelessWidget {
  final String text;

  const SectionHeader(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Text(
        text.toUpperCase(),
        style: AppTypography.mono.copyWith(
          color: AppColors.textMute,
          letterSpacing: 2,
        ),
      ),
    );
  }
}
