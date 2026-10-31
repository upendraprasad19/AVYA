// test/contracts/exercise_animation_view_test.dart
//
// Batch M2a Task 9: ExerciseAnimationView, the one widget that turns a bundled still into an animation. NO HIVE here (the repository
// is a fake that counts calls), so the font failure cache is primed the ordinary way by the first widget test, before anything
// mocks path_provider. Every codec / image-provider wait runs inside `tester.runAsync` (a testWidgets body is fake-async and real
// image decoding never completes there), and every row uses a slug that EXISTS in assets/exercise_stills/ (an absent SvgPicture
// asset once hung the plate harness for minutes; an absent still has never been run here, so no test relies on it).
//
// Lettered cases are the plan's mutation targets: [c] 60 rebuilds, [f] frozen decode failure, [h][q] A shown then B, [i] playing
// decode failure, [p] decode width, [r] throwing evict, [s] second ensure, [t] reduce motion, [u] autoplay false.
import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/exercise_media/exercise_media.dart';
import 'package:icanbefitter/core/services/exercise_media/exercise_media_repository.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/shared/providers/exercise_media_provider.dart';
import 'package:icanbefitter/shared/widgets/exercise_plate/exercise_animation_view.dart';
import 'package:icanbefitter/shared/widgets/exercise_plate/exercise_monogram.dart';

import '../helpers/image_fixture.dart';

const _mediaA = ExerciseMedia(slug: '0001-three-quarter-situp', version: 1);
const _mediaB = ExerciseMedia(slug: '0002-45-degree-side-bend', version: 1);

const _still = Key('exercise-animation-still');
const _playing = Key('exercise-animation-playing');
const _frozen = Key('exercise-animation-frozen');

Uint8List _png() => Uint8List.fromList(kTinyPng);

/// Bytes the image codec refuses.
Uint8List _garbage() => Uint8List.fromList(const [1, 2, 3, 4, 5, 6, 7, 8]);

/// A repository stand-in that counts calls. It has no store, so a store read is not observable here.
class _FakeRepo implements ExerciseMediaRepository {
  _FakeRepo([this.answer]);

  Future<Uint8List?> Function(ExerciseMedia media)? answer;
  bool throwSynchronously = false;
  Object? evictError;
  final List<String> ensured = <String>[];
  final List<String> evicted = <String>[];

  @override
  Future<Uint8List?> ensure(ExerciseMedia media) {
    ensured.add(media.objectName);
    if (throwSynchronously) throw StateError('ensure threw');
    final a = answer;
    return a == null ? Future<Uint8List?>.value(null) : a(media);
  }

  @override
  Future<void> evict(ExerciseMedia media) async {
    evicted.add(media.objectName);
    final e = evictError;
    if (e != null) throw e;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final ValueNotifier<int> _noTick = ValueNotifier<int>(0);

/// Every pump of [tick] builds a FRESH, non-const view instance: a const or identical widget would make Flutter skip
/// `didUpdateWidget`, and the 60-rebuild case would never reach the code it is about.
Widget _app({
  required _FakeRepo repo,
  required ValueNotifier<ExerciseMedia> media,
  ValueNotifier<int>? tick,
  double size = 200,
  bool autoplay = true,
  bool platformOn = true,
  bool reduceMotion = false,
  double dpr = 1,
}) {
  return ProviderScope(
    overrides: [
      exerciseMediaRepositoryProvider.overrideWithValue(repo),
      exerciseAnimationsPlatformEnabledProvider.overrideWithValue(platformOn),
    ],
    child: MaterialApp(
      home: Builder(
        builder: (ctx) => MediaQuery(
          data: MediaQuery.of(ctx).copyWith(disableAnimations: reduceMotion, devicePixelRatio: dpr),
          child: Scaffold(
            body: Center(
              child: ValueListenableBuilder<ExerciseMedia>(
                valueListenable: media,
                builder: (_, m, _) => ValueListenableBuilder<int>(
                  valueListenable: tick ?? _noTick,
                  builder: (_, _, _) => ExerciseAnimationView(
                    media: m,
                    exerciseName: 'Fixture Exercise',
                    size: size,
                    autoplay: autoplay,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// Lets the real engine finish a decode (or fail one), then runs the frames that follow.
Future<void> _settle(WidgetTester t) async {
  await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
  await t.pump();
  await t.pump(const Duration(seconds: 1));
}

Image _playingImage(WidgetTester t) => t.widget<Image>(find.byKey(_playing));

ResizeImage _resize(WidgetTester t) => _playingImage(t).image as ResizeImage;

Uint8List _bytesOf(ResizeImage r) => (r.imageProvider as MemoryImage).bytes;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ---- FIRST, and it ends at once: GoogleFonts cannot fetch in the harness and reports its failure on whichever test is still
  // running when it arrives. A test that waits on real time (runAsync) must never be the one that first renders a font, so this one
  // renders the play button's face (monoXs) and finishes without any real wait, as exercise_plate_widgets_test.dart does. ----
  testWidgets('the play-button font is primed before any test waits on real time', (t) async {
    await t.pumpWidget(MaterialApp(home: Scaffold(body: Text('prime', style: AppTypography.monoXs))));
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text('prime'), findsOneWidget);
  });

  testWidgets('the fixture PNG is a real image the engine decodes (and the garbage bytes are really refused)', (t) async {
    final codec = await t.runAsync(() => ui.instantiateImageCodec(_png()));
    expect(codec, isNotNull);
    final frame = await t.runAsync(() => codec!.getNextFrame());
    expect(frame!.image.width, 1);
    expect(frame.image.height, 1);
    frame.image.dispose();
    codec!.dispose();

    final bad = await t.runAsync(() async {
      try {
        await ui.instantiateImageCodec(_garbage());
        return false;
      } catch (_) {
        return true;
      }
    });
    expect(bad, isTrue, reason: 'the garbage bytes must really fail to decode, or the failure cases prove nothing');
  });

  testWidgets('a repository that answers null keeps the still: no error box, no animation', (t) async {
    final repo = _FakeRepo();
    final media = ValueNotifier<ExerciseMedia>(_mediaA);
    await t.pumpWidget(_app(repo: repo, media: media));
    await t.pump();
    await t.pump(const Duration(seconds: 1));

    expect(repo.ensured, [_mediaA.objectName]);
    expect(find.byKey(_still), findsOneWidget);
    expect(find.byKey(_playing), findsNothing);
    expect(find.byType(ExerciseMonogram), findsNothing);
    final still = t.widget<Image>(find.descendant(of: find.byKey(_still), matching: find.byType(Image)));
    expect((still.image as AssetImage).assetName, _mediaA.stillAsset);
    expect(t.takeException(), isNull);
  });

  testWidgets('bytes swap the still for the animation (key exercise-animation-playing)', (t) async {
    final bytes = _png();
    final repo = _FakeRepo((_) async => bytes);
    final media = ValueNotifier<ExerciseMedia>(_mediaA);
    await t.pumpWidget(_app(repo: repo, media: media));
    await t.pump();
    await t.pump(const Duration(seconds: 1));

    expect(find.byKey(_playing), findsOneWidget);
    expect(find.byKey(_frozen), findsNothing);
    expect(identical(_bytesOf(_resize(t)), bytes), isTrue);
    expect(t.takeException(), isNull);
  });

  group('reduced motion and autoplay', () {
    Future<void> expectFrozenThenPlay(WidgetTester t, _FakeRepo repo, ValueNotifier<ExerciseMedia> media) async {
      await _settle(t);
      expect(find.byKey(_frozen), findsOneWidget);
      expect(find.byKey(_playing), findsNothing);
      expect(find.text('PLAY'), findsOneWidget);
      // The first frame is drawn (a decoded RawImage, no asset still any more).
      final raw = t.widget<RawImage>(find.descendant(of: find.byKey(_frozen), matching: find.byType(RawImage)));
      expect(raw.image, isNotNull);
      expect(find.descendant(of: find.byKey(_frozen), matching: find.byType(Image)), findsNothing);
      final size = t.getSize(find.text('PLAY'));
      expect(size.height, greaterThan(0));

      await t.tap(find.text('PLAY'));
      await t.pump();
      await t.pump(const Duration(seconds: 1));
      expect(find.byKey(_playing), findsOneWidget, reason: 'tapping play starts the animation');
      expect(find.byKey(_frozen), findsNothing);
    }

    testWidgets('[t] under reduce-motion it shows the first frame and a play button; tapping plays', (t) async {
      final repo = _FakeRepo((_) async => _png());
      final media = ValueNotifier<ExerciseMedia>(_mediaA);
      await t.pumpWidget(_app(repo: repo, media: media, reduceMotion: true));
      await t.pump();
      await expectFrozenThenPlay(t, repo, media);
    });

    testWidgets('[u] autoplay: false behaves the same', (t) async {
      final repo = _FakeRepo((_) async => _png());
      final media = ValueNotifier<ExerciseMedia>(_mediaA);
      await t.pumpWidget(_app(repo: repo, media: media, autoplay: false));
      await t.pump();
      await expectFrozenThenPlay(t, repo, media);
    });

    testWidgets('the play button is at least a 44 px touch target', (t) async {
      final repo = _FakeRepo((_) async => _png());
      final media = ValueNotifier<ExerciseMedia>(_mediaA);
      await t.pumpWidget(_app(repo: repo, media: media, reduceMotion: true));
      await t.pump();
      await _settle(t);
      final box = t.getRect(find.ancestor(of: find.text('PLAY'), matching: find.byType(ConstrainedBox)).first);
      expect(box.width, greaterThanOrEqualTo(44));
      expect(box.height, greaterThanOrEqualTo(44));
    });
  });

  group('decode width', () {
    testWidgets('[p] the memory image is a ResizeImage: size x devicePixelRatio, and exactly kMaxAnimatedDecodeWidth at 390 x 3', (t) async {
      final repo = _FakeRepo((_) async => _png());
      final media = ValueNotifier<ExerciseMedia>(_mediaA);
      await t.pumpWidget(_app(repo: repo, media: media, size: 390, dpr: 3));
      await t.pump();
      await t.pump(const Duration(seconds: 1));
      expect(_playingImage(t).image, isA<ResizeImage>());
      expect(_resize(t).width, kMaxAnimatedDecodeWidth, reason: '390 x 3 = 1170 is clamped to the maximum');
      expect(kMaxAnimatedDecodeWidth, 720);
    });

    testWidgets('below the clamp the width is size x devicePixelRatio', (t) async {
      final repo = _FakeRepo((_) async => _png());
      final media = ValueNotifier<ExerciseMedia>(_mediaA);
      await t.pumpWidget(_app(repo: repo, media: media, size: 200, dpr: 2));
      await t.pump();
      await t.pump(const Duration(seconds: 1));
      expect(_resize(t).width, 400);
    });
  });

  group('asking the repository', () {
    testWidgets('[c] 60 rebuilds of the same media, each a fresh widget instance, ask exactly once', (t) async {
      final repo = _FakeRepo();
      final media = ValueNotifier<ExerciseMedia>(_mediaA);
      final tick = ValueNotifier<int>(0);
      await t.pumpWidget(_app(repo: repo, media: media, tick: tick));
      await t.pump();
      for (var i = 1; i <= 60; i++) {
        tick.value = i;
        await t.pump();
      }
      expect(repo.ensured, [_mediaA.objectName]);
    });

    testWidgets('[s] a changed media.objectName asks again, for the new file', (t) async {
      final repo = _FakeRepo();
      final media = ValueNotifier<ExerciseMedia>(_mediaA);
      await t.pumpWidget(_app(repo: repo, media: media));
      await t.pump();
      media.value = _mediaB;
      await t.pump();
      expect(repo.ensured, [_mediaA.objectName, _mediaB.objectName]);
    });

    testWidgets('with the platform switch false it never asks and shows the still at the large size', (t) async {
      final repo = _FakeRepo((_) async => _png());
      final media = ValueNotifier<ExerciseMedia>(_mediaA);
      await t.pumpWidget(_app(repo: repo, media: media, platformOn: false, size: 180));
      await t.pump();
      await t.pump(const Duration(seconds: 1));
      expect(repo.ensured, isEmpty);
      expect(find.byKey(_playing), findsNothing);
      final still = t.widget<Image>(find.descendant(of: find.byKey(_still), matching: find.byType(Image)));
      expect(still.width, 180);
      expect(still.height, 180);
    });

    testWidgets('a repository whose ensure throws (synchronously, or as a failed future) leaves the still and no error', (t) async {
      for (final sync in [true, false]) {
        final repo = _FakeRepo((_) => Future<Uint8List?>.error(StateError('async boom')))..throwSynchronously = sync;
        final media = ValueNotifier<ExerciseMedia>(_mediaA);
        await t.pumpWidget(_app(repo: repo, media: media));
        await t.pump();
        await t.pump(const Duration(seconds: 1));
        expect(find.byKey(_still), findsOneWidget, reason: 'sync=$sync');
        expect(find.byKey(_playing), findsNothing, reason: 'sync=$sync');
        expect(t.takeException(), isNull, reason: 'sync=$sync');
        await t.pumpWidget(const SizedBox());
      }
    });
  });

  group('a slow answer never paints on the wrong exercise', () {
    testWidgets('stale completion: ensure(A) pending, widget moves to B, B completes, then A completes - B stays, A is ignored', (t) async {
      final bytesA = _png();
      final bytesB = _png();
      final done = <String, Completer<Uint8List?>>{
        _mediaA.objectName: Completer<Uint8List?>(),
        _mediaB.objectName: Completer<Uint8List?>(),
      };
      final repo = _FakeRepo((m) => done[m.objectName]!.future);
      final media = ValueNotifier<ExerciseMedia>(_mediaA);
      await t.pumpWidget(_app(repo: repo, media: media));
      await t.pump();
      media.value = _mediaB;
      await t.pump();

      done[_mediaB.objectName]!.complete(bytesB);
      await t.pump();
      await t.pump(const Duration(seconds: 1));
      expect(identical(_bytesOf(_resize(t)), bytesB), isTrue, reason: 'B arrived');

      done[_mediaA.objectName]!.complete(bytesA);
      await t.pump();
      await t.pump(const Duration(seconds: 1));
      expect(identical(_bytesOf(_resize(t)), bytesB), isTrue, reason: 'A, late, must not replace B');
      for (final img in t.widgetList<Image>(find.byType(Image))) {
        final p = img.image;
        if (p is ResizeImage) expect(identical(_bytesOf(p), bytesA), isFalse, reason: 'no Image may wrap the stale bytes');
      }
      expect(t.takeException(), isNull);
    });

    testWidgets('[h][q] A is on screen, the widget moves to B, B pending: B\'s still shows, A\'s frames are gone and A is out of the ImageCache', (t) async {
      final bytesA = _png();
      final pendingB = Completer<Uint8List?>();
      final repo = _FakeRepo((m) => m.objectName == _mediaA.objectName ? Future.value(bytesA) : pendingB.future);
      final media = ValueNotifier<ExerciseMedia>(_mediaA);
      await t.pumpWidget(_app(repo: repo, media: media));
      await t.pump();
      await t.pump(const Duration(seconds: 1));
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
      await t.pump();

      final providerA = _playingImage(t).image;
      final keyA = await t.runAsync(() => providerA.obtainKey(ImageConfiguration.empty));
      expect(imageCache.containsKey(keyA!), isTrue, reason: 'precondition: A is in the ImageCache while it is mounted');

      media.value = _mediaB;
      await t.pump();
      await t.pump(const Duration(seconds: 1));
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await t.pump();

      expect(find.byKey(_playing), findsNothing, reason: 'B has no bytes yet');
      expect(find.byKey(_still), findsOneWidget);
      final still = t.widget<Image>(find.descendant(of: find.byKey(_still), matching: find.byType(Image)));
      expect((still.image as AssetImage).assetName, _mediaB.stillAsset, reason: 'the still is B\'s');
      for (final img in t.widgetList<Image>(find.byType(Image))) {
        final p = img.image;
        if (p is ResizeImage) expect(identical(_bytesOf(p), bytesA), isFalse, reason: 'no Image whose provider wraps A\'s bytes');
      }
      expect(imageCache.containsKey(keyA), isFalse, reason: 'A\'s provider was evicted in the same step that dropped its bytes');
    });
  });

  testWidgets('on dispose the view evicts its provider from the ImageCache', (t) async {
    final repo = _FakeRepo((_) async => _png());
    final media = ValueNotifier<ExerciseMedia>(_mediaA);
    await t.pumpWidget(_app(repo: repo, media: media));
    await t.pump();
    await t.pump(const Duration(seconds: 1));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
    await t.pump();

    final provider = _playingImage(t).image;
    final key = await t.runAsync(() => provider.obtainKey(ImageConfiguration.empty));
    expect(imageCache.containsKey(key!), isTrue, reason: 'precondition: mounted, so cached');

    await t.pumpWidget(const SizedBox());
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    expect(imageCache.containsKey(key), isFalse);
  });

  group('decode failures', () {
    testWidgets('[i] bytes the codec refuses (playing branch): the still stays and evict is called ONCE, however often it rebuilds', (t) async {
      final repo = _FakeRepo((_) async => _garbage());
      final media = ValueNotifier<ExerciseMedia>(_mediaA);
      final tick = ValueNotifier<int>(0);
      await t.pumpWidget(_app(repo: repo, media: media, tick: tick));
      await t.pump();
      await _settle(t);
      for (var i = 1; i <= 5; i++) {
        tick.value = i;
        await t.pump();
      }
      await t.pump(const Duration(seconds: 1));

      expect(repo.evicted, [_mediaA.objectName]);
      expect(find.byKey(_still), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('[f] the same bytes under reduce-motion (frozen branch): the still stays and evict is called ONCE', (t) async {
      final repo = _FakeRepo((_) async => _garbage());
      final media = ValueNotifier<ExerciseMedia>(_mediaA);
      await t.pumpWidget(_app(repo: repo, media: media, reduceMotion: true));
      await t.pump();
      await _settle(t);
      await t.pump(const Duration(seconds: 1));

      expect(repo.evicted, [_mediaA.objectName]);
      expect(find.byKey(_frozen), findsOneWidget);
      expect(find.descendant(of: find.byKey(_frozen), matching: find.byKey(_still)), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('[r] a repository whose evict THROWS leaves no uncaught error and the still stays', (t) async {
      final repo = _FakeRepo((_) async => _garbage())..evictError = StateError('evict threw');
      final media = ValueNotifier<ExerciseMedia>(_mediaA);
      await t.pumpWidget(_app(repo: repo, media: media));
      await t.pump();
      await _settle(t);
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await t.pump();

      expect(repo.evicted, [_mediaA.objectName], reason: 'evict was reached, and it threw');
      expect(find.byKey(_still), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  });
}
