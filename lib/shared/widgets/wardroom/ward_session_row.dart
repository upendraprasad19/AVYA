import 'package:flutter/material.dart';

import '../../../core/theme/colors.dart';
import '../../../core/theme/typography.dart';
import '../../../core/theme/spacing.dart';

/// Single set row in the Active Workout set-log table. Columns:
/// 2-digit padded set number (36 px mono) / weight (1fr Fraunces
/// tabular) / reps (1fr Fraunces tabular) / status (36 px right).
///
/// [WardSessionRowStatus.active] — `accent + '18'` bg, w700 text.
/// [WardSessionRowStatus.done] — ✓ check in `ok`.
/// [WardSessionRowStatus.pending] — ○ circle in `textMute`.
enum WardSessionRowStatus { active, done, pending }

class WardSessionRow extends StatelessWidget {
  const WardSessionRow({
    super.key,
    required this.setNumber,
    required this.weightKg,
    required this.reps,
    required this.status,
    this.onTap,
  });

  final int setNumber;
  final double weightKg;
  final int reps;
  final WardSessionRowStatus status;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final active = status == WardSessionRowStatus.active;
    final bg = active
        ? AppColors.accent.withValues(alpha: 0.09)
        : Colors.transparent;
    final numericWeight = active ? FontWeight.w700 : FontWeight.w500;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(color: bg),
        child: Row(
          children: [
            SizedBox(
              width: 36,
              child: Text(
                'S${setNumber.toString().padLeft(2, '0')}',
                style: AppTypography.mono.copyWith(
                  fontSize: 10,
                  color: active ? AppColors.accent : AppColors.textMute,
                  letterSpacing: 1.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Expanded(
              child: Text(
                _fmt(weightKg),
                style: AppTypography.h3.copyWith(
                  fontSize: 13,
                  color: active ? AppColors.accent : AppColors.textDim,
                  fontWeight: numericWeight,
                  letterSpacing: 0,
                ),
              ),
            ),
            Expanded(
              child: Text(
                reps.toString().padLeft(2, '0'),
                style: AppTypography.h3.copyWith(
                  fontSize: 13,
                  color: active ? AppColors.accent : AppColors.textDim,
                  fontWeight: numericWeight,
                  letterSpacing: 0,
                ),
              ),
            ),
            SizedBox(
              width: 36,
              child: Align(
                alignment: Alignment.centerRight,
                child: _StatusIcon(status),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _fmt(double v) {
    if (v == v.roundToDouble()) return v.toStringAsFixed(0);
    return v.toStringAsFixed(1);
  }
}

class _StatusIcon extends StatelessWidget {
  const _StatusIcon(this.status);
  final WardSessionRowStatus status;

  @override
  Widget build(BuildContext context) {
    switch (status) {
      case WardSessionRowStatus.done:
        return Icon(Icons.check, size: 14, color: AppColors.ok);
      case WardSessionRowStatus.active:
        return Icon(Icons.play_arrow, size: 14, color: AppColors.accent);
      case WardSessionRowStatus.pending:
        return Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.textMute, width: 1.2),
          ),
        );
    }
  }
}

/// Container for a list of [WardSessionRow]s — dashed `line2` border,
/// sharp 2 px corners, no internal dividers (rows render their own
/// optional active-row bg).
class WardSessionTable extends StatelessWidget {
  const WardSessionTable({super.key, required this.rows});

  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(
          color: AppColors.line2,
        ),
        borderRadius: BorderRadius.circular(AppRadius.sharp),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            rows[i],
            if (i < rows.length - 1)
              Container(height: 1, color: AppColors.line3),
          ],
        ],
      ),
    );
  }
}
