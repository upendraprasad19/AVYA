import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import 'package:icanbefitter/core/constants/app_constants.dart';
import 'package:icanbefitter/core/constants/purchase_mode.dart';
import 'package:icanbefitter/core/copy/progress_photo_copy.dart';
import 'package:icanbefitter/core/services/subscription_service.dart';

import '../../../core/theme/colors.dart';
import '../../../core/theme/spacing.dart';
import '../../../core/theme/typography.dart';
import '../../../shared/widgets/error_state.dart';
import '../../../shared/widgets/paywall_sheet.dart';
import '../providers/profile_provider.dart';
import '../repositories/progress_photo_repository.dart';

/// Full-screen progress photos gallery (F19).
///
/// Who sees what (OI-348 Landing 3c, founder calls of 2026-11-26):
///  - Everyone: the gallery (or the empty state), long-press delete and the Add
///    button. Viewing is free.
///  - PRO (server-verified, `gateAndVerify(featureProgressPhotos)`, `pro`):
///    uploads with no cap.
///  - Not PRO, a lapsed PRO included (`free`): one photo per IST week. The Add
///    button asks `ensureFreeSlotOpen` BEFORE the body area and the picker; a
///    used slot shows [ProgressPhotoCopy.weeklyUsed] (with GO PRO only when the
///    build can sell PRO, ADR-0022). The database enforces the same cap at both
///    doors (the progress-photos free weekly cap migration), so the client
///    check is a courtesy.
/// The hub row pushes here for everyone and makes no PRO decision. The write
/// action (`_onAddPhoto`) runs the gate again, because a subscription can lapse
/// or start while the screen stays open (rule 19).
///
/// ONE WRITER. `_reload` is the only code that assigns `_access`, `_photos` and
/// `_error` (apart from the optimistic tile removal in `_delete`). Every trigger
/// (entry, Retry, the upgrade listener, a delete, a capture, a refusal) calls it;
/// it takes a sequence number first and drops its own result after any await if a
/// newer call has started or the screen is gone, so two async paths cannot write
/// out of order. A failed read never reads as "no photos": it keeps the photos on
/// screen (snackbar) or shows the error state; only a SUCCESSFUL empty read
/// reaches the empty state (class 2.49).
///
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

/// Where the screen stands. `checking`: a reload is deciding. `pro`: uploads
/// uncapped. `free`: not PRO (a lapsed PRO included): one photo per IST week.
enum _Access { checking, pro, free }

class _ProgressPhotosScreenState extends ConsumerState<ProgressPhotosScreen> {
  final _repo = ProgressPhotoRepository.instance;
  List<Map<String, dynamic>>? _photos;
  String? _error;
  bool _uploading = false;

  /// The Add button's own gate (`_onAddPhoto`) is in flight. A stale verify
  /// cache plus a slow network makes it wait up to 10 s, and a second tap in that
  /// window would run a second gate and open a second Camera / Gallery sheet.
  bool _gating = false;
  _Access _access = _Access.checking;

  /// `_reload` bookkeeping. `_seq`: the newest call's number; `_inFlight`: how
  /// many calls are running; `_lastVerdictPro`: the gate's verdict at the end of
  /// the last FULL reload; `_dirty`/`_reranOnce`: a subscription flip that
  /// arrived mid-reload (see the listener in `build`).
  int _seq = 0;
  int _inFlight = 0;

  /// How many FULL reloads (ones that run the gate) are running. A reload that
  /// arrives with a `knownPro` verdict while one is running must not trust that
  /// verdict: the full one may be about to say the user just became PRO, and the
  /// newer call would supersede it with the stale answer.
  int _fullInFlight = 0;
  bool _lastVerdictPro = false;
  bool _dirty = false;
  bool _reranOnce = false;

  static const Duration _readTimeout = Duration(seconds: 20);
  static const Duration _verifyTimeout = Duration(seconds: 10);

  @override
  void initState() {
    super.initState();
    // `_access` starts at `checking`, so the spinner is already up: no setState
    // inside initState.
    _reload(keepGallery: true);
  }

  /// The only writer of `_access` / `_photos` / `_error`.
  ///
  /// [knownPro]: reuse the verdict of the last full reload instead of running
  /// the gate again (after a delete or a capture, which only need a re-read, and
  /// from the Add button's `onFree`). [keepGallery]: leave the current gallery on
  /// screen until the single `setState` at the end (false shows the spinner).
  /// [userInitiated]: false only for the one re-run the listener schedules.
  Future<void> _reload({
    bool keepGallery = false,
    bool? knownPro,
    bool userInitiated = true,
  }) async {
    if (userInitiated) _reranOnce = false;
    final gen = ++_seq;
    _inFlight++;
    final isFull = knownPro == null || _fullInFlight > 0;
    if (isFull) _fullInFlight++;
    try {
      if (!keepGallery) {
        setState(() {
          _access = _Access.checking;
          _error = null;
        });
      }
      bool? pro = isFull ? null : knownPro;
      if (pro == null) {
        // `gateAndVerify` always runs exactly one callback before its Future
        // completes (a locally-free user synchronously; a locally-PRO user after
        // a server verify with a 10 s timeout that falls back to onPro). The
        // callbacks only record the verdict.
        await SubscriptionService.instance.gateAndVerify(
          AppConstants.featureProgressPhotos,
          onPro: () => pro = true,
          onFree: () => pro = false,
        );
      }
      if (!mounted || gen != _seq) return;
      final verdict = pro;
      if (verdict == null) throw StateError('PRO gate dispatched no verdict');
      List<Map<String, dynamic>>? photos;
      try {
        photos = await _repo.listStrict().timeout(_readTimeout);
      } catch (e) {
        debugPrint('[ProgressPhotosScreen._reload] read failed: $e');
      }
      if (!mounted || gen != _seq) return;
      _lastVerdictPro = verdict;
      final held = _photos != null && _photos!.isNotEmpty;
      setState(() {
        _access = verdict ? _Access.pro : _Access.free;
        if (photos != null) {
          _photos = photos;
          _error = null;
        } else {
          // A failed read is not "no photos": keep what is on screen.
          _error = held ? null : 'Couldn\'t load photos';
        }
      });
      if (photos == null && held) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Couldn\'t refresh your photos')),
        );
      }
    } catch (e) {
      debugPrint('[ProgressPhotosScreen._reload] $e');
      if (!mounted || gen != _seq) return;
      final held = _photos != null && _photos!.isNotEmpty;
      setState(() {
        _access = _lastVerdictPro ? _Access.pro : _Access.free;
        _error = held ? null : 'Couldn\'t load photos';
      });
    } finally {
      _inFlight--;
      if (isFull) _fullInFlight--;
      final rerun = mounted && _inFlight == 0 && _dirty && !_lastVerdictPro &&
          !_reranOnce;
      if (_inFlight == 0) _dirty = false;
      if (rerun) {
        _reranOnce = true;
        unawaited(_reload(keepGallery: true, userInitiated: false));
      }
    }
  }

  Future<void> _capture(ImageSource source) async {
    // Ask for the body area label first so the metadata is complete.
    final area = await _pickBodyArea();
    if (area == null || !mounted) return;

    setState(() => _uploading = true);
    try {
      final String? id;
      try {
        id = await _repo.capture(source: source, bodyArea: area);
      } on ProgressPhotoProRequiredException {
        await _onProRefused();
        return;
      } catch (_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Upload failed — try again')),
        );
        return;
      }
      if (!mounted) return;
      if (id == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Upload failed — try again')),
        );
        return;
      }
      await _reload(keepGallery: true, knownPro: _lastVerdictPro);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  /// The server refused a new photo (not PRO and this IST week's free photo is
  /// already held). Three outcomes, none of which opens the paywall by itself:
  ///  1. a payment is in flight (the subscription row is not written yet): say so,
  ///     change nothing;
  ///  2. otherwise ask the server (forced, 10 s, a timeout counts as still-PRO,
  ///     as in `gateAndVerify`): it says NOT PRO -> the weekly-cap snackbar and
  ///     a reload as free;
  ///  3. it says PRO (or could not be reached: `verifyFromServer` trusts the local
  ///     state offline): "couldn't confirm", no state change.
  Future<void> _onProRefused() async {
    if (!mounted) return;
    if (SubscriptionService.instance.isPaymentInFlight) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'Your PRO is still activating — give it a minute and try again.')),
      );
      return;
    }
    final stillPro = await SubscriptionService.instance
        .verifyFromServer(force: true)
        .timeout(_verifyTimeout, onTimeout: () => true);
    if (!mounted) return;
    if (stillPro) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'We couldn\'t confirm your PRO just now — check your subscription in Profile, or try again in a minute.')),
      );
      return;
    }
    _showWeeklyUsed();
    await _reload(keepGallery: true, knownPro: false);
  }

  /// The free weekly cap is reached. The GO PRO action exists only in a build
  /// that can sell PRO (ADR-0022, `showsUpgradeAffordance`).
  void _showWeeklyUsed() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text(ProgressPhotoCopy.weeklyUsed),
        action: showsUpgradeAffordance()
            ? SnackBarAction(
                label: ProgressPhotoCopy.goPro,
                onPressed: () => showPaywallSheet(context,
                    feature: ProgressPhotoCopy.paywallFeature),
              )
            : null,
      ),
    );
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
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Couldn\'t delete that photo — try again')),
      );
      return;
    }
    // Take the tile off at once, so a failed refresh cannot leave a ghost tile
    // whose long-press would delete an id that is already gone.
    setState(() => _photos = [
          for (final p in _photos ?? const <Map<String, dynamic>>[])
            if (p['id'] != id) p
        ]);
    await _reload(keepGallery: true, knownPro: _lastVerdictPro);
  }

  @override
  Widget build(BuildContext context) {
    // The weekly-cap snackbar's GO PRO opens the paywall, which cannot be awaited
    // (`showPaywallSheet` returns void). A completed purchase flips this provider
    // (`onStateChanged`, app.dart), so a free user who has just become PRO gets
    // the screen re-decided: server-verified, same as on entry.
    // Fires only for a flip TO PRO. While a reload is already running the flip is
    // remembered (`_dirty`) instead of starting a second one, and at most ONE
    // re-run follows if that reload ended not-PRO; `pro` and `checking` are
    // never listener sources.
    ref.listen<SubscriptionInfoData>(subscriptionInfoProvider, (previous, next) {
      if (!next.isPro) return;
      if (_inFlight > 0) {
        _dirty = true;
        return;
      }
      if (_access == _Access.free) {
        unawaited(_reload(keepGallery: true));
      }
    });
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
      // Everyone gets the button once the screen has decided; a tap runs the
      // gate again and, for a free user, the weekly slot check before anything
      // is picked.
      floatingActionButton: _access == _Access.checking
          ? null
          : (_uploading || _gating)
              ? const FloatingActionButton(
                  onPressed: null,
                  backgroundColor: AppColors.accent,
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.black),
                  ),
                )
              : FloatingActionButton.extended(
                  onPressed: _onAddPhoto,
                  backgroundColor: AppColors.accent,
                  icon: const Icon(Icons.add_a_photo, color: Colors.black),
                  label: const Text('Add photo',
                      style: TextStyle(
                          color: Colors.black, fontWeight: FontWeight.w800)),
                ),
      body: _buildBody(),
    );
  }

  /// The write action runs the gate again: a subscription can lapse (or start)
  /// while this screen stays open. The verify is cached for 5 minutes AFTER a
  /// 200 answer only (`verifyFromServer` stamps the cache nowhere else), so a tap
  /// can wait on the server for up to 10 s: the button shows the busy spinner
  /// meanwhile and a second tap does nothing (`_gating`). A free verdict runs the
  /// weekly slot check (also under `_gating`) BEFORE the source sheet and the
  /// body area; a used slot shows the weekly-cap snackbar and picks nothing. A
  /// verdict that differs from the screen's re-decides it through `_reload`.
  Future<void> _onAddPhoto() async {
    if (_gating) return;
    setState(() => _gating = true);
    var proceed = false;
    try {
      bool? pro;
      await SubscriptionService.instance.gateAndVerify(
        AppConstants.featureProgressPhotos,
        onPro: () => pro = true,
        onFree: () => pro = false,
      );
      final verdict = pro;
      if (!mounted || verdict == null) return;
      if (verdict != _lastVerdictPro) {
        unawaited(_reload(keepGallery: true, knownPro: verdict));
      }
      if (!verdict) {
        try {
          await _repo.ensureFreeSlotOpen();
        } on PhotoQuotaException {
          _showWeeklyUsed();
          return;
        }
        if (!mounted) return;
      } else {
        // PRO has no slot to free, but its orphans still cost storage: the
        // same bounded sweep (this IST week, an hour old, no row), unawaited.
        unawaited(_repo.cleanupOrphanedStorage());
      }
      proceed = true;
    } finally {
      if (mounted) setState(() => _gating = false);
    }
    if (proceed && mounted) await _pickAndCapture();
  }

  Future<void> _pickAndCapture() async {
    final src = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: AppColors.card,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt, color: AppColors.accent),
              title: const Text('Camera',
                  style: TextStyle(color: AppColors.textPrimary)),
              onTap: () => Navigator.of(context).pop(ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library, color: AppColors.accent),
              title: const Text('Gallery',
                  style: TextStyle(color: AppColors.textPrimary)),
              onTap: () => Navigator.of(context).pop(ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (src != null) await _capture(src);
  }

  /// The free user's one-line rule, above the grid and in the empty state.
  Widget _freeCaption() => Text(
        ProgressPhotoCopy.freeCaption,
        key: const ValueKey('progress_photos_free_caption'),
        textAlign: TextAlign.center,
        style: AppTypography.monoXs
            .copyWith(color: AppColors.textDim, letterSpacing: 1.5),
      );

  Widget _buildBody() {
    final grid = _buildGallery();
    if (_access != _Access.free || _error != null || _photos == null) {
      return grid;
    }
    if (_photos!.isEmpty) return grid; // the empty state carries the caption
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.screenPadding,
              AppSpacing.screenPadding, AppSpacing.screenPadding, 0),
          child: _freeCaption(),
        ),
        Expanded(child: grid),
      ],
    );
  }

  Widget _buildGallery() {
    if (_access == _Access.checking) {
      return const Center(
          child: CircularProgressIndicator(color: AppColors.accent));
    }
    if (_error != null) {
      return ErrorState(
        title: 'Couldn\'t load photos',
        subtitle: _error,
        onRetry: () => _reload(keepGallery: _photos?.isNotEmpty ?? false),
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
              if (_access == _Access.free) ...[
                const SizedBox(height: 12),
                _freeCaption(),
              ],
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
