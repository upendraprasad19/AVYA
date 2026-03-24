import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/shared/widgets/tap_scale.dart';

/// Compact toggleable quick action card matching the mockup (qb class).
/// Icon + label, toggles on/off style on tap.
class QuickActionButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? iconColor;
  final bool initiallyActive;

  const QuickActionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.iconColor,
    this.initiallyActive = false,
  });

  @override
  State<QuickActionButton> createState() => _QuickActionButtonState();
}

class _QuickActionButtonState extends State<QuickActionButton> {
  late bool _isActive;

  @override
  void initState() {
    super.initState();
    _isActive = widget.initiallyActive;
  }

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: TapScale(
        onTap: () {
          setState(() => _isActive = !_isActive);
          widget.onTap();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 4),
          decoration: BoxDecoration(
            color: _isActive
                ? AppColors.accent.withValues(alpha: 0.07)
                : AppColors.card,
            borderRadius: BorderRadius.circular(11),
            border: Border.all(
              color: _isActive
                  ? AppColors.accent.withValues(alpha: 0.28)
                  : AppColors.border,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                widget.icon,
                size: 17,
                color: _isActive ? AppColors.accent : AppColors.textSecondary,
              ),
              const SizedBox(height: 4),
              Text(
                widget.label,
                style: GoogleFonts.getFont(
                  'DM Sans',
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.2,
                  color:
                      _isActive ? AppColors.accent : AppColors.textSecondary,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
