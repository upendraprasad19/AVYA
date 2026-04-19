import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/features/nutrition/providers/nutrition_provider.dart';
import 'package:icanbefitter/shared/widgets/wardroom/wardroom.dart';

/// Bottom sheet for quickly adding water intake from the home screen.
class WaterQuickSheet extends ConsumerStatefulWidget {
  const WaterQuickSheet({super.key});

  @override
  ConsumerState<WaterQuickSheet> createState() => _WaterQuickSheetState();
}

class _WaterQuickSheetState extends ConsumerState<WaterQuickSheet> {
  String? _addedLabel;

  void _addWater(int ml, String label) async {
    await ref.read(waterIntakeProvider.notifier).addWater(ml);
    setState(() => _addedLabel = label);
    Future.delayed(const Duration(milliseconds: 900), () {
      if (mounted) setState(() => _addedLabel = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    final currentMl = ref.watch(waterIntakeProvider);
    const targetMl = 3000;
    final progress = (currentMl / targetMl).clamp(0.0, 1.0);

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.card,
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(AppRadius.card)),
      ),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.gutter,
        12,
        AppSpacing.gutter,
        24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.line2,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),

          // Title — mono caps eyebrow
          Text(
            'LOG WATER',
            style: AppTypography.mono.copyWith(
              color: AppColors.accent,
              letterSpacing: 3,
            ),
          ),
          const SizedBox(height: 14),

          // Current progress — Fraunces numeric
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: _formatMl(currentMl),
                  style: AppTypography.h1.copyWith(
                    color: AppColors.accent,
                  ),
                ),
                TextSpan(
                  text: ' / ${_formatMl(targetMl)} ML',
                  style: AppTypography.monoXs.copyWith(
                    color: AppColors.textMute,
                    letterSpacing: 2,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Progress bar — WardBar
          WardBar(
            pct: progress,
            height: 6,
            color: AppColors.info,
          ),
          const SizedBox(height: 10),

          // Feedback text
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: _addedLabel != null
                ? Text(
                    '\u2713 ADDED $_addedLabel',
                    key: ValueKey(_addedLabel),
                    style: AppTypography.mono.copyWith(
                      color: AppColors.ok,
                      letterSpacing: 2,
                    ),
                  )
                : const SizedBox(height: 16, key: ValueKey('empty')),
          ),
          const SizedBox(height: 12),

          // Quick-add buttons row — sharp 2-px outline tiles
          Row(
            children: [
              _WaterButton(
                label: '150ML',
                subtitle: 'SMALL GLASS',
                icon: Icons.local_cafe_outlined,
                onTap: () => _addWater(150, '150ml'),
              ),
              const SizedBox(width: 8),
              _WaterButton(
                label: '250ML',
                subtitle: 'GLASS',
                icon: Icons.local_drink_outlined,
                onTap: () => _addWater(250, '250ml'),
              ),
              const SizedBox(width: 8),
              _WaterButton(
                label: '500ML',
                subtitle: 'BOTTLE',
                icon: Icons.water_drop_outlined,
                onTap: () => _addWater(500, '500ml'),
              ),
              const SizedBox(width: 8),
              _WaterButton(
                label: '750ML',
                subtitle: 'LARGE',
                icon: Icons.sports_bar_outlined,
                onTap: () => _addWater(750, '750ml'),
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  String _formatMl(int ml) {
    if (ml >= 1000) {
      final thousands = ml ~/ 1000;
      final hundreds = (ml % 1000).toString().padLeft(3, '0');
      return '$thousands,$hundreds';
    }
    return ml.toString();
  }
}

class _WaterButton extends StatelessWidget {
  final String label;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  const _WaterButton({
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
          decoration: BoxDecoration(
            color: AppColors.bgRaise,
            borderRadius: BorderRadius.circular(AppRadius.sharp),
            border: Border.all(color: AppColors.line2),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: AppColors.accent),
              const SizedBox(height: 6),
              Text(
                label,
                style: AppTypography.mono.copyWith(
                  color: AppColors.textPrimary,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: AppTypography.monoXs.copyWith(
                  color: AppColors.textMute,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
