import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/theme/colors.dart';
import '../../../core/theme/spacing.dart';
import '../../../core/theme/typography.dart';
import '../../../shared/widgets/error_state.dart';
import '../../../shared/widgets/paywall_sheet.dart';
import '../repositories/progress_photo_repository.dart';

/// Full-screen progress photos gallery (F19).
///
/// PRO-gated at the entry point (see `ProgressPhotosCard` + profile menu).
/// Reads/writes via `ProgressPhotoRepository` which in turn handles:
///   - Supabase Storage upload + signed-URL read (`progress-photos` bucket)
///   - `progress_photos` metadata row (migration 022)
///
/// Thumbnails lazy-load from signed URLs (1-hour TTL). Metadata query is
/// cheap; photo bytes stream as the user scrolls.
class ProgressPhotosScreen extends ConsumerStatefulWidget {
  const ProgressPhotosScreen({super.key});

  @override
  ConsumerState<ProgressPhotosScreen> createState() =>
      _ProgressPhotosScreenState();
}

class _ProgressPhotosScreenState extends ConsumerState<ProgressPhotosScreen> {
  final _repo = ProgressPhotoRepository.instance;
  List<Map<String, dynamic>>? _photos;
  String? _error;
  bool _uploading = false;

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

  Future<void> _capture(ImageSource source) async {
    // Ask for the body area label first so the metadata is complete.
    final area = await _pickBodyArea();
    if (area == null || !mounted) return;

    setState(() => _uploading = true);
    String? id;
    try {
      id = await _repo.capture(source: source, bodyArea: area);
    } on PhotoQuotaException catch (e) {
      // Daily cap hit (2/day free, 5/day PRO). Before F40 the throw propagated
      // uncaught and left _uploading=true (spinner stuck forever) with no
      // paywall/snackbar. Free users get the paywall for the higher PRO cap;
      // PRO users (already at the top cap) get a neutral come-back-tomorrow nudge.
      if (!mounted) return;
      setState(() => _uploading = false);
      if (e.isPro) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Daily photo limit reached — back tomorrow.')),
        );
      } else {
        showPaywallSheet(context, feature: 'Progress Photos');
      }
      return;
    } catch (_) {
      if (!mounted) return;
      setState(() => _uploading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Upload failed — try again')),
      );
      return;
    }
    if (!mounted) return;
    setState(() => _uploading = false);

    if (id == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Upload failed — try again')),
      );
      return;
    }
    await _load();
  }

  Future<String?> _pickBodyArea() async {
    final options = ['Front', 'Side', 'Back'];
    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.card,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Text('Which angle?',
                style: AppTypography.body.copyWith(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
            const SizedBox(height: 12),
            for (final opt in options)
              ListTile(
                title: Text(opt,
                    style: AppTypography.body.copyWith(fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                onTap: () => Navigator.of(context).pop(opt.toLowerCase()),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _delete(String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        title: Text('Delete photo?',
            style: AppTypography.body.copyWith(fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Delete',
                  style: TextStyle(color: AppColors.red))),
        ],
      ),
    );
    if (confirm != true) return;
    final ok = await _repo.delete(id);
    if (ok) await _load();
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
              'DOSSIER \u00B7 PLATES',
              style: AppTypography.monoXs.copyWith(
                color: AppColors.accent,
                letterSpacing: 2.5,
              ),
            ),
            const SizedBox(height: 2),
            Text('Progress photos', style: AppTypography.h3),
          ],
        ),
      ),
      floatingActionButton: _uploading
          ? const FloatingActionButton(
              onPressed: null,
              backgroundColor: AppColors.accent,
              child: SizedBox(
                width: 20,
                height: 20,
                child:
                    CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
              ),
            )
          : FloatingActionButton.extended(
              onPressed: () async {
                final src = await showModalBottomSheet<ImageSource>(
                  context: context,
                  backgroundColor: AppColors.card,
                  builder: (_) => SafeArea(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ListTile(
                          leading: const Icon(Icons.camera_alt,
                              color: AppColors.accent),
                          title: const Text('Camera',
                              style: TextStyle(color: AppColors.textPrimary)),
                          onTap: () =>
                              Navigator.of(context).pop(ImageSource.camera),
                        ),
                        ListTile(
                          leading: const Icon(Icons.photo_library,
                              color: AppColors.accent),
                          title: const Text('Gallery',
                              style: TextStyle(color: AppColors.textPrimary)),
                          onTap: () =>
                              Navigator.of(context).pop(ImageSource.gallery),
                        ),
                      ],
                    ),
                  ),
                );
                if (src != null) await _capture(src);
              },
              backgroundColor: AppColors.accent,
              icon: const Icon(Icons.add_a_photo, color: Colors.black),
              label: const Text('Add photo',
                  style: TextStyle(color: Colors.black, fontWeight: FontWeight.w800)),
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
              const Icon(Icons.photo_library_outlined,
                  size: 48, color: AppColors.textSecondary),
              const SizedBox(height: 12),
              Text('No photos yet',
                  style: AppTypography.body.copyWith(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
              const SizedBox(height: 6),
              Text(
                'Track your progress visually.\nTap the button to add your first photo.',
                textAlign: TextAlign.center,
                style: AppTypography.body.copyWith(fontSize: 13, color: AppColors.textDim),
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
        final area = (p['body_area'] as String? ?? '').toUpperCase();
        return GestureDetector(
          onLongPress: () => _delete(p['id'] as String),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (url != null)
                  Image.network(url, fit: BoxFit.cover)
                else
                  Container(color: AppColors.card),
                Positioned(
                  left: 6,
                  bottom: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.bg.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      area,
                      style: AppTypography.monoXs.copyWith(fontWeight: FontWeight.w800, color: AppColors.accent, letterSpacing: 0.5),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
