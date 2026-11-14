import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/colors.dart';
import '../../../core/theme/spacing.dart';
import '../../../core/theme/typography.dart';
import '../../../shared/widgets/error_state.dart';
import '../../ai_coach/repositories/coach_media_repository.dart';

/// Saved coach-media photos gallery (Unit 8, coach-media-consent, OI-25).
///
/// Photos land here only when the user explicitly consents via the
/// "Save this photo?" chip on an AI Coach chat bubble — there is no
/// capture flow on this screen itself (contrast [ProgressPhotosScreen],
/// which both captures AND lists). No metadata table: reads directly
/// from the `coach-media` Storage bucket via [CoachMediaRepository.list],
/// mirroring `ProgressPhotoRepository.list()`'s signed-URL pattern.
class SavedCoachPhotosScreen extends ConsumerStatefulWidget {
  const SavedCoachPhotosScreen({super.key});

  @override
  ConsumerState<SavedCoachPhotosScreen> createState() =>
      _SavedCoachPhotosScreenState();
}

class _SavedCoachPhotosScreenState
    extends ConsumerState<SavedCoachPhotosScreen> {
  final _repo = CoachMediaRepository.instance;
  List<Map<String, dynamic>>? _photos;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final photos = await _repo.list();
      if (!mounted) return;
      setState(() {
        _photos = photos;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Couldn\'t load photos');
    }
  }

  Future<void> _delete(String path) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        title: Text('Delete photo?',
            style: AppTypography.body
                .copyWith(fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Delete', style: TextStyle(color: AppColors.red))),
        ],
      ),
    );
    if (confirm != true) return;
    final ok = await _repo.delete(path);
    if (ok) {
      await _load();
      return;
    }
    if (!mounted) return;
    // B-pass finding (2026-07-30) — mirrors _onSaveCoachMedia's own
    // failure-feedback pattern (chat_area.dart): a mutation that fails
    // silently is indistinguishable from one that succeeded but didn't
    // refresh, per this repo's own documented save-confirmation pitfall.
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Couldn\'t delete that photo — please try again.',
          style: AppTypography.body.copyWith(color: AppColors.bad),
        ),
        backgroundColor: AppColors.card,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'DOSSIER · COACH LOG',
              style: AppTypography.monoXs.copyWith(
                color: AppColors.accent,
                letterSpacing: 2.5,
              ),
            ),
            const SizedBox(height: 2),
            Text('Saved photos', style: AppTypography.h3),
          ],
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_error != null) {
      return ErrorState(
        title: 'Couldn\'t load photos',
        subtitle: _error,
        onRetry: _load,
      );
    }
    if (_photos == null) {
      return const Center(
          child: CircularProgressIndicator(color: AppColors.accent));
    }
    if (_photos!.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.screenPadding),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.bookmark_border,
                  size: 48, color: AppColors.textSecondary),
              const SizedBox(height: 12),
              Text('No saved photos yet',
                  style: AppTypography.body.copyWith(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary)),
              const SizedBox(height: 6),
              Text(
                'Photos you save from AI Coach chat\nwill appear here.',
                textAlign: TextAlign.center,
                style: AppTypography.body
                    .copyWith(fontSize: 13, color: AppColors.textDim),
              ),
            ],
          ),
        ),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.all(AppSpacing.screenPadding),
      itemCount: _photos!.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 0.8,
      ),
      itemBuilder: (ctx, idx) {
        final p = _photos![idx];
        final url = p['signed_url'] as String?;
        final path = p['path'] as String;
        return GestureDetector(
          onLongPress: () => _delete(path),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: url != null
                ? Image.network(url, fit: BoxFit.cover)
                : Container(color: AppColors.card),
          ),
        );
      },
    );
  }
}
