/// Slim banner shown when the sync queue has pending work.
///
/// Rendered at the top of screens where the user is likely to notice
/// and care — Home and Profile. Zero height when sync is idle, so it
/// doesn't disturb the layout when nothing's pending.
///
/// Copy rules (CLAUDE.md §11): no "restart the app" — map to
/// actionable user copy only.
///
/// Reference: docs/superpowers/specs/2026-04-17-sync-reliability.md Pillar C.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/colors.dart';
import '../providers/sync_state_provider.dart';

class SyncBanner extends ConsumerWidget {
  const SyncBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(syncStateProvider);
    return switch (state) {
      SyncIdle() => const SizedBox.shrink(),
      SyncQueued(:final pendingCount) =>
        _QueuedBanner(count: pendingCount),
    };
  }
}

class _QueuedBanner extends ConsumerWidget {
  final int count;
  const _QueuedBanner({required this.count});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final copy = count == 1
        ? '1 change waiting to sync'
        : '$count changes waiting to sync';

    return Material(
      color: AppColors.accentTint,
      child: InkWell(
        onTap: () => ref.read(syncStateProvider.notifier).retryNow(),
        child: Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          alignment: Alignment.centerLeft,
          decoration: const BoxDecoration(
            border: Border(
              bottom: BorderSide(color: AppColors.border, width: 1),
            ),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.cloud_queue_rounded,
                size: 16,
                color: AppColors.accent,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  copy,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.accent,
                  ),
                ),
              ),
              const Text(
                'Retry',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                  color: AppColors.accent,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
