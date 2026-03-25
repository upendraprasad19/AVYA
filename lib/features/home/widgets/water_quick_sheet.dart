import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/features/nutrition/providers/nutrition_provider.dart';

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
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenPadding,
        12,
        AppSpacing.screenPadding,
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
              color: AppColors.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),

          // Title
          Text(
            'LOG WATER',
            style: GoogleFonts.getFont(
              'DM Sans',
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 16),

          // Current progress text
          Text(
            '${_formatMl(currentMl)} / ${_formatMl(targetMl)} ml',
            style: GoogleFonts.getFont(
              'DM Sans',
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: AppColors.accent,
            ),
          ),
          const SizedBox(height: 10),

          // Progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              backgroundColor: AppColors.input,
              valueColor: const AlwaysStoppedAnimation<Color>(AppColors.accent),
            ),
          ),
          const SizedBox(height: 8),

          // Feedback text
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: _addedLabel != null
                ? Text(
                    '\u2713 Added $_addedLabel',
                    key: ValueKey(_addedLabel),
                    style: GoogleFonts.getFont(
                      'DM Sans',
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.green,
                    ),
                  )
                : const SizedBox(height: 16, key: ValueKey('empty')),
          ),
          const SizedBox(height: 12),

          // Quick-add buttons row
          Row(
            children: [
              _WaterButton(
                ml: 150,
                label: '150ml',
                subtitle: 'Small glass',
                icon: Icons.local_cafe_outlined,
                onTap: () => _addWater(150, '150ml'),
              ),
              const SizedBox(width: 8),
              _WaterButton(
                ml: 250,
                label: '250ml',
                subtitle: 'Glass',
                icon: Icons.local_drink_outlined,
                onTap: () => _addWater(250, '250ml'),
              ),
              const SizedBox(width: 8),
              _WaterButton(
                ml: 500,
                label: '500ml',
                subtitle: 'Bottle',
                icon: Icons.water_drop_outlined,
                onTap: () => _addWater(500, '500ml'),
              ),
              const SizedBox(width: 8),
              _WaterButton(
                ml: 750,
                label: '750ml',
                subtitle: 'Large',
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
  final int ml;
  final String label;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  const _WaterButton({
    required this.ml,
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
            color: AppColors.bg,
            borderRadius: BorderRadius.circular(100),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: AppColors.accent),
              const SizedBox(height: 4),
              Text(
                label,
                style: GoogleFonts.getFont(
                  'DM Sans',
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
              Text(
                subtitle,
                style: GoogleFonts.getFont(
                  'DM Sans',
                  fontSize: 8,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
