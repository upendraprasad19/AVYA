import 'package:flutter/material.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/shared/widgets/wardroom/wardroom.dart';

/// Exercise card used in the template builder.
class ExerciseCard extends StatelessWidget {
  final String name;
  final String? category;
  final String loggingType;
  final int sets;
  final String reps;
  final int restSeconds;
  final VoidCallback? onRemove;
  final VoidCallback? onTap;

  const ExerciseCard({
    super.key,
    required this.name,
    this.category,
    required this.loggingType,
    this.sets = 3,
    this.reps = '10',
    this.restSeconds = 90,
    this.onRemove,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return WardCard(
      variant: WardCardVariant.inset,
      onTap: onTap,
      child: Row(
        children: [
          const Icon(Icons.drag_handle, color: AppColors.textGhost, size: 20),
          const SizedBox(width: 12),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: AppTypography.h3,
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    if (category != null)
                      WardChip(label: category!),
                    WardChip(label: _formatLoggingType(loggingType)),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  '$sets sets x $reps ${loggingType == 'timed' ? 'sec' : 'reps'} · ${restSeconds}s rest',
                  style: AppTypography.bodySm.copyWith(
                    color: AppColors.textDim,
                  ),
                ),
              ],
            ),
          ),

          if (onRemove != null)
            IconButton(
              onPressed: onRemove,
              icon: const Icon(Icons.close, color: AppColors.bad, size: 18),
              constraints: const BoxConstraints(),
              padding: EdgeInsets.zero,
            ),
        ],
      ),
    );
  }

  String _formatLoggingType(String type) {
    return type.replaceAll('_', ' ');
  }
}
