import 'package:flutter/material.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'loading_skeleton.dart';

/// Full-screen shimmer loading skeleton with multiple card placeholders.
///
/// Use this as a loading state for tab screens that read from Hive.
class ScreenLoadingSkeleton extends StatelessWidget {
  /// Number of skeleton cards to show. Defaults to 4.
  final int cardCount;

  const ScreenLoadingSkeleton({super.key, this.cardCount = 4});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.screenPadding),
      physics: const NeverScrollableScrollPhysics(),
      children: [
        // Header shimmer
        const LoadingSkeleton(width: 160, height: 18),
        const SizedBox(height: 6),
        const LoadingSkeleton(width: 100, height: 12),
        const SizedBox(height: 18),
        // Card shimmers
        for (int i = 0; i < cardCount; i++) ...[
          const SkeletonCard(),
          const SizedBox(height: AppSpacing.sectionGap),
        ],
      ],
    );
  }
}
