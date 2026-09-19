import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/features/train/providers/video_render_provider.dart';

class VideoShareButton extends ConsumerWidget {
  const VideoShareButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final renderState = ref.watch(videoRenderNotifierProvider);

    if (renderState.status == VideoRenderStatus.idle) {
      return const SizedBox.shrink();
    }

    if (renderState.isLoading) {
      return _LoadingButton(
        label: renderState.status == VideoRenderStatus.queued
            ? 'Queueing video...'
            : 'Rendering...',
      );
    }

    if (renderState.status == VideoRenderStatus.ready &&
        renderState.outputUrl != null) {
      return _ShareButton(url: renderState.outputUrl!);
    }

    if (renderState.status == VideoRenderStatus.failed) {
      return _ErrorButton(
        onRetry: () => ref.read(videoRenderNotifierProvider.notifier).reset(),
      );
    }

    return const SizedBox.shrink();
  }
}

class _LoadingButton extends StatelessWidget {
  final String label;
  const _LoadingButton({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: AppColors.accentTint,
        border: Border.all(color: AppColors.accent.withValues(alpha:0.3)),
        borderRadius: BorderRadius.circular(100),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(AppColors.accent),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            label,
            style: const TextStyle(
              color: AppColors.accent,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _ShareButton extends StatelessWidget {
  final String url;
  const _ShareButton({required this.url});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Share.share(
        'Check out my workout! $url',
        subject: 'My ICANBEFITTER Workout',
      ),
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          color: AppColors.accent,
          borderRadius: BorderRadius.circular(100),
          boxShadow: [
            BoxShadow(
              color: AppColors.accent.withValues(alpha:0.3),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.video_library_rounded, color: Colors.black, size: 18),
            SizedBox(width: 8),
            Text(
              'Share Video',
              style: TextStyle(
                color: Colors.black,
                fontSize: 14,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorButton extends StatelessWidget {
  final VoidCallback onRetry;
  const _ErrorButton({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onRetry,
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          color: AppColors.red.withValues(alpha:0.1),
          border: Border.all(color: AppColors.red.withValues(alpha:0.3)),
          borderRadius: BorderRadius.circular(100),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.refresh_rounded, color: AppColors.red, size: 16),
            SizedBox(width: 8),
            Text(
              'Video failed — tap to dismiss',
              style: TextStyle(
                color: AppColors.red,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
