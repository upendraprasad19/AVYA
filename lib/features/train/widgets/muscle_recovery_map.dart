import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';

class MuscleRecoveryData {
  final String muscle;
  final String status; // 'ready', 'recovering', 'trained'
  final int hoursSinceTraining;

  const MuscleRecoveryData({
    required this.muscle,
    required this.status,
    required this.hoursSinceTraining,
  });
}

class MuscleRecoveryMap extends StatelessWidget {
  final List<MuscleRecoveryData> recoveryData;

  const MuscleRecoveryMap({
    super.key,
    required this.recoveryData,
  });

  static const _statusColors = <String, Color>{
    'ready': AppColors.green,
    'recovering': AppColors.orange,
    'trained': AppColors.red,
  };

  static const _statusLabels = <String, String>{
    'ready': 'Ready',
    'recovering': 'Recovering',
    'trained': 'Trained',
  };

  String _formatHours(int hours) {
    if (hours < 1) return 'just now';
    if (hours < 24) return '${hours}h ago';
    final days = hours ~/ 24;
    return '${days}d ago';
  }

  Widget _buildRow(MuscleRecoveryData item) {
    final color = _statusColors[item.status] ?? AppColors.textSecondary;
    final label = _statusLabels[item.status] ?? item.status;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              item.muscle,
              style: GoogleFonts.getFont(
                'DM Sans',
                fontSize: 13,
                fontWeight: FontWeight.w400,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          Text(
            label,
            style: GoogleFonts.getFont(
              'DM Sans',
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 42,
            child: Text(
              _formatHours(item.hoursSinceTraining),
              textAlign: TextAlign.right,
              style: GoogleFonts.getFont(
                'DM Sans',
                fontSize: 10,
                fontWeight: FontWeight.w400,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final useGrid = recoveryData.length > 4;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.cardPadding),
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppRadius.cardM),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'MUSCLE RECOVERY',
            style: GoogleFonts.getFont(
              'DM Sans',
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: AppColors.textSecondary,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 10),
          if (useGrid)
            Wrap(
              spacing: 12,
              children: recoveryData.map((item) {
                return SizedBox(
                  width: (MediaQuery.of(context).size.width -
                          AppSpacing.screenPadding * 2 -
                          AppSpacing.cardPadding * 2 -
                          12) /
                      2,
                  child: _buildRow(item),
                );
              }).toList(),
            )
          else
            Column(
              children: recoveryData.map(_buildRow).toList(),
            ),
        ],
      ),
    );
  }
}
