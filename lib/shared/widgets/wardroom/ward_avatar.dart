import 'package:flutter/material.dart';

import '../../../core/theme/colors.dart';
import '../../../core/theme/typography.dart';

/// Circular avatar with Wardroom styling — gold ring at 40% alpha on a
/// soft gold tint background, initial set in Fraunces when no image is
/// provided. Falls through to [image] when a photo URL is supplied.
class WardAvatar extends StatelessWidget {
  const WardAvatar({
    super.key,
    this.initial = 'U',
    this.size = 44,
    this.image,
  });

  final String initial;
  final double size;
  final ImageProvider? image;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.accentSoft,
        border: Border.all(
          color: AppColors.accent.withValues(alpha: 0.4),
          width: 2,
        ),
        image: image == null
            ? null
            : DecorationImage(image: image!, fit: BoxFit.cover),
      ),
      alignment: Alignment.center,
      child: image != null
          ? null
          : Text(
              initial.isEmpty ? 'U' : initial.substring(0, 1).toUpperCase(),
              style: AppTypography.h2.copyWith(
                fontSize: size * 0.4,
                color: AppColors.accent,
                height: 1,
              ),
            ),
    );
  }
}
