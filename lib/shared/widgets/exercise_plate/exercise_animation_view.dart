// lib/shared/widgets/exercise_plate/exercise_animation_view.dart
//
// One exercise animation (Batch M2a, Task 9). It shows the BUNDLED STILL at once, asks the repository for the animation ONCE
// (`initState`, and again in `didUpdateWidget` only when `media.objectName` changed), and cross-fades to the animation when the
// bytes arrive. If anything goes wrong (no bytes, a decode failure, a platform with animations off) the still stays.
//
// RULES THAT HOLD THIS TOGETHER (each is pinned by a lettered case in exercise_animation_view_test.dart):
//   - STALE COMPLETION: the view remembers the object name it asked for and ignores the answer if it is unmounted or the media
//     changed meanwhile, so a slow answer for A never paints on B.
//   - ONE repository, read ONCE in `initState` into a field. Every later call (the `ensure` completion, the microtask evict, the
//     dispose-time eviction) uses that field and never `ref` after an await or after unmount (Riverpod refuses it).
//   - The view never raises an unhandled error: the `ensure` future and the microtask `evict` future both carry a `.catchError`.
//   - DECODE WIDTH: the animation is decoded at `size * devicePixelRatio`, clamped to `kMaxAnimatedDecodeWidth` (720; Task 1's S6
//     verdict may lower it to 360), through a `ResizeImage` built ONCE per bytes value and kept in a field, so dispose can evict
//     it from the `ImageCache` (a cached completer keeps every decoded frame alive with no listeners).
//   - REDUCED MOTION: `autoplay: false` and `MediaQuery.disableAnimationsOf` both mean the FIRST FRAME plus a play button (44 px
//     minimum touch target); tapping it starts the animation. The frame is decoded with `ui.instantiateImageCodec`.
//   - DECODE FAILURE: both branches call `repository.evict(media)` once (per bytes value) and keep the still; the repository bans
//     the name for the session.
//   - MEDIA CHANGE: the previous bytes, the frozen frame and the play state are cleared in the SAME setState that requests the new
//     file, so the view shows B's still and never A's frames, and A's provider is evicted from the `ImageCache`.
//   - A platform whose switch is false never calls `ensure` and shows the still (the stills-only platform, Task 1's ladder).
//
// Review-only limit (stated, not tested): that every `ui.Image` is disposed in every path is read in review; the VM has no handle
// count to assert.
import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:icanbefitter/core/services/exercise_media/exercise_media.dart';
import 'package:icanbefitter/core/services/exercise_media/exercise_media_repository.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/shared/providers/exercise_media_provider.dart';
import 'package:icanbefitter/shared/widgets/exercise_plate/exercise_monogram.dart';

/// The widest an animation is ever decoded. A 720 x 720 source decoded at 1170 would hold 48 frames at about 5 MB each.
const int kMaxAnimatedDecodeWidth = 720;

const Duration _kCrossFade = Duration(milliseconds: 250);

class ExerciseAnimationView extends ConsumerStatefulWidget {
  const ExerciseAnimationView({
    super.key,
    required this.media,
    required this.exerciseName,
    required this.size,
    this.autoplay = true,
    this.fit = BoxFit.contain,
  });

  final ExerciseMedia media;
  final String exerciseName;
  final double size;
  final bool autoplay;
  final BoxFit fit;

  @override
  ConsumerState<ExerciseAnimationView> createState() => _ExerciseAnimationViewState();
}

class _ExerciseAnimationViewState extends ConsumerState<ExerciseAnimationView> {
  late final ExerciseMediaRepository _repo;
  late final bool _platformOn;

  Uint8List? _bytes;
  ImageProvider? _provider;
  bool _evictScheduled = false;
  bool _playTapped = false;
  ui.Image? _frame;
  bool _frameRequested = false;

  /// Bumped on every media change and on dispose; a decode that finishes under an older value is thrown away.
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _repo = ref.read(exerciseMediaRepositoryProvider);
    _platformOn = ref.read(exerciseAnimationsPlatformEnabledProvider);
    if (_platformOn) _request();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reduced motion can be switched on while bytes are already here.
    _maybeDecodeFrozenFrame();
  }

  @override
  void didUpdateWidget(covariant ExerciseAnimationView old) {
    super.didUpdateWidget(old);
    if (old.media.objectName == widget.media.objectName) return;
    _generation++;
    final oldProvider = _provider;
    setState(() {
      _bytes = null;
      _provider = null;
      _playTapped = false;
      _evictScheduled = false;
      _frameRequested = false;
      _frame?.dispose();
      _frame = null;
    });
    if (oldProvider != null) unawaited(oldProvider.evict().catchError((Object _) => false));
    if (_platformOn) _request();
  }

  @override
  void dispose() {
    _generation++;
    final provider = _provider;
    if (provider != null) unawaited(provider.evict().catchError((Object _) => false));
    _frame?.dispose();
    _frame = null;
    super.dispose();
  }

  // ---- asking for the animation -----------------------------------------------------------------------------------------

  void _request() {
    final requested = widget.media.objectName;
    unawaited(Future<Uint8List?>.sync(() => _repo.ensure(widget.media)).then((bytes) {
      // A slow answer for A must never paint on B.
      if (!mounted || widget.media.objectName != requested) return;
      if (bytes == null) return;
      _onBytes(bytes);
    }).catchError((Object _) {}));
  }

  int _decodeWidth() =>
      (widget.size * MediaQuery.devicePixelRatioOf(context)).round().clamp(1, kMaxAnimatedDecodeWidth).toInt();

  bool get _frozen => !widget.autoplay || MediaQuery.disableAnimationsOf(context);

  void _onBytes(Uint8List bytes) {
    final provider = ResizeImage(MemoryImage(bytes), width: _decodeWidth());
    setState(() {
      _bytes = bytes;
      _provider = provider;
      _evictScheduled = false;
      _frameRequested = false;
    });
    _maybeDecodeFrozenFrame();
  }

  // ---- the frozen branch ---------------------------------------------------------------------------------------------------------

  void _maybeDecodeFrozenFrame() {
    final bytes = _bytes;
    if (bytes == null || _frame != null || _frameRequested || !_frozen) return;
    _frameRequested = true;
    unawaited(_decodeFirstFrame(bytes, widget.media, _generation).catchError((Object _) {}));
  }

  Future<void> _decodeFirstFrame(Uint8List bytes, ExerciseMedia media, int generation) async {
    ui.Image image;
    try {
      final codec = await ui.instantiateImageCodec(bytes, targetWidth: _decodeWidth());
      try {
        image = (await codec.getNextFrame()).image;
      } finally {
        codec.dispose();
      }
    } catch (_) {
      // A decode failure keeps the still and bans the name for the session (once per bytes value).
      if (mounted && generation == _generation) _scheduleEvictOnce();
      return;
    }
    if (!mounted || generation != _generation) {
      image.dispose(); // produced after dispose or after the media changed: disposed at once, not stored
      return;
    }
    setState(() {
      _frame?.dispose();
      _frame = image;
    });
  }

  // ---- decode failure --------------------------------------------------------------------------------------------------------------

  /// Once per bytes value. A builder can run many times and must not start work synchronously, hence the microtask.
  void _scheduleEvictOnce() {
    if (_evictScheduled) return;
    _evictScheduled = true;
    final media = widget.media;
    Future<void>.microtask(() {
      unawaited(Future<void>.sync(() => _repo.evict(media)).catchError((Object _) {}));
    });
  }

  // ---- build ----------------------------------------------------------------------------------------------------------------------------

  Widget _still() {
    return KeyedSubtree(
      key: const ValueKey<String>('exercise-animation-still'),
      child: Image.asset(
        widget.media.stillAsset,
        width: widget.size,
        height: widget.size,
        fit: widget.fit,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => ExerciseMonogram(name: widget.exerciseName, size: widget.size),
      ),
    );
  }

  Widget _playButton() {
    return Semantics(
      button: true,
      label: 'Play',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _playTapped = true),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.bgDeep.withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: AppColors.accent),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.play_arrow_rounded, color: AppColors.accent, size: 22),
                  const SizedBox(width: 4),
                  Text('PLAY', style: AppTypography.monoXs.copyWith(color: AppColors.accent, letterSpacing: 2)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = _provider;
    Widget face = _still();
    if (_platformOn && provider != null) {
      if (_frozen && !_playTapped) {
        final frame = _frame;
        face = Stack(
          key: const Key('exercise-animation-frozen'),
          fit: StackFit.expand,
          children: [
            if (frame != null) _FrozenFrame(image: frame, fit: widget.fit) else _still(),
            Center(child: _playButton()),
          ],
        );
      } else {
        face = Image(
          key: const Key('exercise-animation-playing'),
          image: provider,
          width: widget.size,
          height: widget.size,
          fit: widget.fit,
          gaplessPlayback: true,
          errorBuilder: (_, _, _) {
            _scheduleEvictOnce();
            return _still();
          },
        );
      }
    }
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedSwitcher(duration: _kCrossFade, child: face),
    );
  }
}

/// Paints one decoded frame. It owns a CLONE of the handle it is given, so the view can dispose its own handle the moment the
/// media changes while this widget is still fading out inside the `AnimatedSwitcher` (painting a disposed image asserts).
class _FrozenFrame extends StatefulWidget {
  const _FrozenFrame({required this.image, required this.fit});

  final ui.Image image;
  final BoxFit fit;

  @override
  State<_FrozenFrame> createState() => _FrozenFrameState();
}

class _FrozenFrameState extends State<_FrozenFrame> {
  late ui.Image _own = widget.image.clone();

  @override
  void didUpdateWidget(covariant _FrozenFrame old) {
    super.didUpdateWidget(old);
    if (!identical(old.image, widget.image)) {
      _own.dispose();
      _own = widget.image.clone();
    }
  }

  @override
  void dispose() {
    _own.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RawImage(image: _own, fit: widget.fit);
}
