import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import 'package:icanbefitter/core/constants/app_constants.dart';
import 'package:icanbefitter/core/services/subscription_service.dart';
import 'package:icanbefitter/shared/widgets/pro_locked_overlay.dart';

import '../../../core/theme/colors.dart';
import '../../../core/theme/spacing.dart';
import '../../../core/theme/typography.dart';
import '../../../shared/widgets/error_state.dart';
import '../../../shared/widgets/paywall_sheet.dart';
import '../providers/profile_provider.dart';
import '../repositories/progress_photo_repository.dart';

/// Full-screen progress photos gallery (F19).
///
/// Who sees what (founder decisions 5 and 6 of 2026-10-06, OI-314):
///  - PRO (server-verified, `gateAndVerify(featureProgressPhotos)`): the gallery
///    and the Add button (`granted`).
///  - A LAPSED user who still holds photos: the gallery, long-press delete, and an
///    Add button that only leads to the paywall (`readOnly`). The database refuses
///    a new photo without an active subscription (migration 154) but never a read
///    or a delete.
///  - Nobody-has-photos and not PRO (a never-PRO user, or a lapsed one who has
///    deleted everything): the locked card with an Upgrade button (`denied`), and
///    NO write control.
/// The hub row no longer gates; it pushes here for everyone, so the screen owns
/// the decision (also for the web address `#/profile/progress-photos`, edited into
/// an app that is already open; a fresh load goes through `/restoring` and lands
/// on Home). The write action (`_onAddPhoto`) runs the gate again, because a
/// subscription can lapse while the screen stays open and a Storage write is the
/// reason `progress_photos` is server-verified (rule 19).
///
/// ONE WRITER. `_reload` is the only code that assigns `_access`, `_photos` and
/// `_error` (apart from the optimistic tile removal in `_delete`). Every trigger
/// (entry, Retry, the upgrade listener, a delete, a capture, a refusal) calls it;
/// it takes a sequence number first and drops its own result after any await if a
/// newer call has started or the screen is gone, so two async paths cannot write
/// out of order. A failed read never reads as "no photos": it keeps the photos on
/// screen (snackbar) or shows the error state; only a SUCCESSFUL empty read
/// reaches `denied` or the empty state (class 2.49).
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

/// Where the screen stands. `checking`: a reload is deciding. `granted`: PRO.
/// `readOnly`: not PRO, photos held (or the read failed): view and delete.
/// `denied`: not PRO and a successful read found none: the locked card.
enum _Access { checking, granted, readOnly, denied }

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
        if (photos != null) {
          _photos = photos;
          _error = null;
          _access = verdict
              ? _Access.granted
              : (photos.isEmpty ? _Access.denied : _Access.readOnly);
        } else {
          // A failed read is not "no photos": keep what is on screen.
          _access = verdict ? _Access.granted : _Access.readOnly;
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
        _access = _lastVerdictPro ? _Access.granted : _Access.readOnly;
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
      } on PhotoQuotaException {
        // Daily cap hit (5/day, IST). Only PRO users reach `capture`.
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Daily photo limit reached — back tomorrow.')),
        );
        return;
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

  /// The server refused a new photo (migration 154). Three outcomes, none of
  /// which sends a payer to the paywall:
  ///  1. a payment is in flight (the subscription row is not written yet): say so,
  ///     change nothing;
  ///  2. otherwise ask the server (forced, 10 s, a timeout counts as still-PRO,
  ///     as in `gateAndVerify`): it says NOT PRO -> the paywall and a reload;
  ///  3. it says PRO (or could not be reached: `verifyFromServer` trusts the local
  ///     state offline): "couldn't confirm", no paywall, no state change.
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
    showPaywallSheet(context, feature: 'Progress Photos');
    await _reload(keepGallery: true, knownPro: false);
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
    // The locked card's Upgrade button opens the paywall, which cannot be awaited
    // (`showPaywallSheet` returns void). A completed purchase flips this provider
    // (`onStateChanged`, app.dart), so a user who is not PRO and has just become
    // PRO gets the screen re-decided: server-verified, same as on entry.
    // Fires only for a flip TO PRO. While a reload is already running the flip is
    // remembered (`_dirty`) instead of starting a second one, and at most ONE
    // re-run follows if that reload ended not-PRO; `granted` and `checking` are
    // never listener sources.
    ref.listen<SubscriptionInfoData>(subscriptionInfoProvider, (previous, next) {
      if (!next.isPro) return;
      if (_inFlight > 0) {
        _dirty = true;
        return;
      }
      if (_access == _Access.denied || _access == _Access.readOnly) {
        unawaited(_reload(keepGallery: _access == _Access.readOnly));
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
      // No button for a user the gate refused who holds no photos: a free user
      // must not be offered a Storage write (rule 19). A lapsed user who holds
      // photos gets one; its tap goes through the gate to the paywall, never to a
      // picker.
      floatingActionButton: !(_access == _Access.granted ||
              (_access == _Access.readOnly && (_photos?.isNotEmpty ?? false)))
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

  /// The write action runs the gate again: a subscription that lapses while this
  /// screen stays open must not reach `capture`. The verify is cached for 5
  /// minutes AFTER a 200 answer only (`verifyFromServer` stamps the cache nowhere
  /// else), so a tap can wait on the server for up to 10 s: the button shows the
  /// busy spinner meanwhile and a second tap does nothing (`_gating`). A user the
  /// gate refuses gets the paywall and a reload with the known verdict (their
  /// photos, if any, stay on screen).
  Future<void> _onAddPhoto() async {
    if (_gating) return;
    setState(() => _gating = true);
    try {
      await SubscriptionService.instance.gateAndVerify(
        AppConstants.featureProgressPhotos,
        onPro: () {
          if (!mounted) return;
          _pickAndCapture();
        },
        onFree: () {
          if (!mounted) return;
          showPaywallSheet(context, feature: 'Progress Photos');
          // Re-decide through the one writer (the verdict is known: not PRO), so a
          // lapsed user's photos stay on screen.
          unawaited(_reload(keepGallery: true, knownPro: false));
        },
      );
    } finally {
      if (mounted) setState(() => _gating = false);
    }
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

  /// What a user the gate refused sees (only the typed web address or a mid-
  /// session lapse gets here: the hub row shows a free user the paywall without
  /// opening this screen). The design system's PRO locked card, with nothing
  /// real behind it: no photo is read or shown.
  Widget _buildLocked() {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.screenPadding),
      child: ProLockedOverlay(
        featureLabel: 'Progress Photos',
        description: 'Track your transformation visually',
        minHeight: 240,
        onUpgradeTap: () =>
            showPaywallSheet(context, feature: 'Progress Photos'),
        child: const ColoredBox(color: AppColors.card),
      ),
    );
  }

  Widget _buildBody() {
    switch (_access) {
      case _Access.checking:
        return const Center(
            child: CircularProgressIndicator(color: AppColors.accent));
      case _Access.denied:
        return _buildLocked();
      case _Access.granted:
      case _Access.readOnly:
        break;
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
