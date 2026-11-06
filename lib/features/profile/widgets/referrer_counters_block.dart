import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:icanbefitter/core/copy/referral_copy.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/features/profile/models/referrer_summary.dart';
import 'package:icanbefitter/features/profile/providers/referral_summary_provider.dart';

/// The referrer's counters in the Invite Friends sheet (unit C, OI-336):
/// friends joined, subscribed, PRO days earned, and a pending count only when
/// above zero.
///
/// Hidden when the figures are unknown (any failure, anonymous, switched off,
/// or the RPC absent) and when no friend has joined (no zero-state
/// discouragement). A skeleton of stat tiles shows while loading, never a bare
/// spinner. Wrapped tiles, not one long mono line, so it fits 360 dp at 2x
/// text.
class ReferrerCountersBlock extends ConsumerWidget {
  const ReferrerCountersBlock({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(referrerSummaryProvider);
    return async.when(
      loading: () => const _Skeleton(),
      error: (_, _) => const SizedBox.shrink(),
      data: (summary) {
        if (summary == null || summary.joined == 0) {
          return const SizedBox.shrink();
        }
        return _Counters(summary: summary);
      },
    );
  }
}

class _Counters extends StatelessWidget {
  const _Counters({required this.summary});
  final ReferrerSummary summary;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: ReferralCopy.countersSemantics(
        joined: summary.joined,
        subscribed: summary.subscribed,
        daysEarned: summary.daysEarned,
        pending: summary.pending,
      ),
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.only(top: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                ReferralCopy.countersEyebrow,
                style: AppTypography.mono.copyWith(
                  fontSize: 10,
                  letterSpacing: 2,
                  color: AppColors.textDim,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _Tile(
                      key: const ValueKey('referrer-tile-joined'),
                      label: ReferralCopy.labelJoined,
                      value: summary.joined),
                  _Tile(
                      key: const ValueKey('referrer-tile-subscribed'),
                      label: ReferralCopy.labelSubscribed,
                      value: summary.subscribed),
                  _Tile(
                      key: const ValueKey('referrer-tile-days'),
                      label: ReferralCopy.labelDaysEarned,
                      value: summary.daysEarned),
                  if (summary.pending > 0)
                    _Tile(
                        key: const ValueKey('referrer-tile-pending'),
                        label: ReferralCopy.labelPending,
                        value: summary.pending),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({super.key, required this.label, required this.value});
  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 96),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.input,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$value',
              style: AppTypography.h2.copyWith(color: AppColors.accent)),
          const SizedBox(height: 2),
          Text(
            label,
            style: AppTypography.mono.copyWith(
              fontSize: 10,
              letterSpacing: 1.0,
              color: AppColors.textDim,
            ),
          ),
        ],
      ),
    );
  }
}

class _Skeleton extends StatelessWidget {
  const _Skeleton();

  @override
  Widget build(BuildContext context) {
    Widget tile() => Container(
          width: 96,
          height: 56,
          decoration: BoxDecoration(
            color: AppColors.input,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.border),
          ),
        );
    return Padding(
      key: const ValueKey('referrer-counters-skeleton'),
      padding: const EdgeInsets.only(top: 20),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [tile(), tile(), tile()],
      ),
    );
  }
}
