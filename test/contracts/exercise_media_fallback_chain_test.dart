// test/contracts/exercise_media_fallback_chain_test.dart
//
// Batch M2a Task 9: the face a library row shows, in the thumb and in the sheet, with the two kill switches.
//   thumb face order: plates off -> monogram; animations on AND the row has media -> the bundled still (it WINS over a plate, C3);
//   else a plate when the row has one; else the monogram.
//   sheet: a media row shows ONE animated picture instead of START/END while animations are on; with them off the sheet is exactly
//   today's (the drawings, or the monogram and NO DRAWING YET).
//
// HARNESS: copied from exercise_plate_widgets_test.dart / exercise_plate_sheet_test.dart, whose headers explain both traps.
//  1. Hive is opened LAZILY inside runAsync, never in setUpAll (a testWidgets body is fake-async; real disk I/O never completes).
//  2. The FIRST test renders every AppTypography style used below with NO path_provider mock installed, so GoogleFonts fails and
//     caches the failure the ordinary way; once the mock is up it would surface as a test error instead.
// Every row a test seeds uses a slug that exists in assets/exercise_stills/ and assets/plates/. No test relies on an ABSENT asset
// (an absent SvgPicture asset hung the plate harness for 6m35s).
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:icanbefitter/core/services/exercise_media/exercise_media.dart';
import 'package:icanbefitter/core/services/exercise_media/exercise_media_repository.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/shared/providers/exercise_media_provider.dart';
import 'package:icanbefitter/shared/widgets/exercise_plate/exercise_animation_view.dart';
import 'package:icanbefitter/shared/widgets/exercise_plate/exercise_monogram.dart';
import 'package:icanbefitter/shared/widgets/exercise_plate/exercise_plate_sheet.dart';
import 'package:icanbefitter/shared/widgets/exercise_plate/exercise_plate_thumb.dart';

const _mediaOnly = 'M2 Fixture Media Only';
const _both = 'M2 Fixture Media And Plate';
const _mediaOnlyMedia = ExerciseMedia(slug: '0001-three-quarter-situp', version: 1);
const _bothMedia = ExerciseMedia(slug: '0002-45-degree-side-bend', version: 1);

Directory? _tempDir;

Future<void> _ensureHive() async {
  if (_tempDir != null) return;
  final dir = await Directory.systemTemp.createTemp('media_fallback');
  _tempDir = dir;
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (_) async => dir.path,
  );
  Hive.init(dir.path);
  await HiveService.instance.init();
  final lib = (jsonDecode(File('assets/data/exercise_library.json').readAsStringSync()) as List).cast<Map<String, dynamic>>();
  await HiveService.instance.exerciseBox.putAll({for (final e in lib) e['id'] as String: e});
  // The real library has NO row carrying both a plate and an animation, so the C3 case seeds one. `bench-press` is a PAIR
  // (START and END), which is what the sheet shows when the animation is switched off.
  await HiveService.instance.exerciseBox.put('M2_MEDIA_ONLY', {
    'id': 'M2_MEDIA_ONLY',
    'name': _mediaOnly,
    'media_slug': _mediaOnlyMedia.slug,
    'media_version': _mediaOnlyMedia.version,
  });
  await HiveService.instance.exerciseBox.put('M2_BOTH', {
    'id': 'M2_BOTH',
    'name': _both,
    'demo_slug': 'bench-press',
    'demo_pair': true,
    'media_slug': _bothMedia.slug,
    'media_version': _bothMedia.version,
  });
}

/// Records calls; answers null, so the sheet keeps the still and nothing decodes.
class _FakeRepo implements ExerciseMediaRepository {
  final List<String> ensured = <String>[];

  @override
  Future<Uint8List?> ensure(ExerciseMedia media) {
    ensured.add(media.objectName);
    return Future<Uint8List?>.value(null);
  }

  @override
  Future<void> evict(ExerciseMedia media) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: Center(child: child)));

/// The flag is cleared even if an expect throws (the happy-path delete alone would leak it into later tests).
Future<void> _setFlag(WidgetTester t, String flag) async {
  addTearDown(() async => HiveService.instance.configBox.delete(flag));
  await t.runAsync(() async => HiveService.instance.configBox.put(flag, true));
}

Future<void> _pumpThumb(WidgetTester t, String name) async {
  await t.runAsync(_ensureHive);
  await t.pumpWidget(_host(ExercisePlateThumb(exerciseName: name, size: 44)));
  await t.pump();
  await t.pump(const Duration(milliseconds: 100));
}

AssetImage _stillOf(WidgetTester t) {
  final image = t.widget<Image>(find.descendant(of: find.byType(ExercisePlateThumb), matching: find.byType(Image)));
  return image.image as AssetImage;
}

Decoration _tile(WidgetTester t) {
  final box = t.widget<DecoratedBox>(find.descendant(of: find.byType(ExercisePlateThumb), matching: find.byType(DecoratedBox)).first);
  return box.decoration;
}

Future<_FakeRepo> _openSheet(WidgetTester t, String name, {Size? surface}) async {
  await t.runAsync(_ensureHive);
  if (surface != null) {
    await t.binding.setSurfaceSize(surface);
    addTearDown(() => t.binding.setSurfaceSize(null));
  }
  final repo = _FakeRepo();
  await t.pumpWidget(ProviderScope(
    overrides: [
      exerciseMediaRepositoryProvider.overrideWithValue(repo),
      exerciseAnimationsPlatformEnabledProvider.overrideWithValue(true),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (ctx) => TextButton(
            onPressed: () => ExercisePlateSheet.show(ctx, name),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  ));
  await t.tap(find.text('open'));
  await t.pump();
  await t.pump(const Duration(milliseconds: 400));
  return repo;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDownAll(() async {
    if (_tempDir == null) return;
    await Hive.close();
    if (_tempDir!.existsSync()) {
      try {
        _tempDir!.deleteSync(recursive: true);
      } catch (_) {}
    }
  });

  // ---- FIRST, Hive-free: renders EVERY AppTypography style the sheet uses (see the header). ----
  testWidgets('the monogram and every sheet font render before any path_provider mock exists', (t) async {
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ExerciseMonogram(name: 'Surya Namaskar', size: 96),
              Text('prime mono', style: AppTypography.mono),
              Text('prime monoXs', style: AppTypography.monoXs),
              Text('prime bodySm', style: AppTypography.bodySm),
              Text('prime body', style: AppTypography.body),
            ],
          ),
        ),
      ),
    ));
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text('SN'), findsOneWidget);
  });

  group('thumb face order', () {
    testWidgets('a row with media and both flags unset shows the BUNDLED STILL (an asset Image), not a plate', (t) async {
      await _pumpThumb(t, _mediaOnly);
      expect(find.byType(Image), findsOneWidget);
      expect(_stillOf(t).assetName, _mediaOnlyMedia.stillAsset);
      expect(find.byType(SvgPicture), findsNothing);
      expect(find.byType(ExerciseMonogram), findsNothing);
    });

    testWidgets('[m] a row with BOTH a plate and media shows the still: the animation wins (C3)', (t) async {
      await _pumpThumb(t, _both);
      expect(find.byType(Image), findsOneWidget);
      expect(_stillOf(t).assetName, _bothMedia.stillAsset);
      expect(find.byType(SvgPicture), findsNothing, reason: 'the plate must not show when the row has an animation');
    });

    testWidgets('disable_exercise_animations: the plate when the row has a drawing, else the monogram', (t) async {
      await t.runAsync(_ensureHive);
      await _setFlag(t, 'disable_exercise_animations');
      await _pumpThumb(t, _both);
      expect(find.byType(SvgPicture), findsOneWidget, reason: 'the row has a drawing');
      expect(find.byType(Image), findsNothing);

      await _pumpThumb(t, _mediaOnly);
      expect(find.byType(SvgPicture), findsNothing);
      expect(find.byType(Image), findsNothing);
      expect(find.byType(ExerciseMonogram), findsOneWidget, reason: 'no drawing, so the monogram');
    });

    testWidgets('disable_exercise_plates: the monogram for every row, no asset loads', (t) async {
      await t.runAsync(_ensureHive);
      await _setFlag(t, 'disable_exercise_plates');
      for (final name in [_mediaOnly, _both, 'Wall Sit']) {
        await _pumpThumb(t, name);
        expect(find.byType(Image), findsNothing, reason: name);
        expect(find.byType(SvgPicture), findsNothing, reason: name);
        expect(find.byType(ExerciseMonogram), findsOneWidget, reason: name);
      }
    });

    testWidgets('a plate-only row is unchanged, and a row with neither shows the monogram', (t) async {
      await _pumpThumb(t, 'Wall Sit');
      expect(find.byType(SvgPicture), findsOneWidget);
      expect(find.byType(Image), findsNothing);

      await _pumpThumb(t, 'Totally Invented Exercise');
      expect(find.byType(SvgPicture), findsNothing);
      expect(find.byType(Image), findsNothing);
      expect(find.byType(ExerciseMonogram), findsOneWidget);
    });

    testWidgets('the thumb RE-RESOLVES the media when the exercise name changes', (t) async {
      await _pumpThumb(t, _mediaOnly);
      expect(find.byType(Image), findsOneWidget, reason: 'precondition: the still shows');
      await t.pumpWidget(_host(const ExercisePlateThumb(exerciseName: 'Totally Invented Exercise', size: 44)));
      await t.pump();
      await t.pump(const Duration(milliseconds: 100));
      expect(find.byType(Image), findsNothing, reason: 'a swap reuses the State; didUpdateWidget must re-resolve the media');
      expect(find.byType(ExerciseMonogram), findsOneWidget);
    });

    testWidgets('[n] C15: the still tile\'s frame (colour, border, radius) EQUALS the plate tile\'s at size 44', (t) async {
      await _pumpThumb(t, _both);
      final still = _tile(t);
      await t.runAsync(_ensureHive);
      await _setFlag(t, 'disable_exercise_animations');
      await _pumpThumb(t, _both);
      final plate = _tile(t);

      expect(still, isA<BoxDecoration>());
      final d = still as BoxDecoration;
      expect(d.color, AppColors.cardHi);
      expect(d.border, isNotNull);
      expect(d.borderRadius, isNotNull);
      expect(still, plate);
    });

    test('the still face declares an errorBuilder that falls back to the plate when the row has one, else the monogram (PRESENCE ONLY)', () {
      // Stated limit: an absent asset hangs the harness for minutes (recorded in exercise_plate_widgets_test.dart), so no
      // behavioural missing-asset case exists. This pins that the fallback is written, not that it runs.
      final src = File('lib/shared/widgets/exercise_plate/exercise_plate_thumb.dart')
          .readAsStringSync()
          .replaceAll(RegExp(r'//.*'), '');
      final start = src.indexOf('Widget _stillFace(');
      expect(start, greaterThan(0), reason: 'the still face method must exist');
      final face = src.substring(start);
      final i = face.indexOf('errorBuilder:');
      expect(i, greaterThan(0), reason: 'the still face has no errorBuilder');
      final handler = face.substring(i, (i + 260).clamp(0, face.length).toInt());
      expect(handler.contains('_plate.hasArtwork'), isTrue);
      expect(handler.contains('_plateFace()'), isTrue);
      expect(handler.contains('ExerciseMonogram'), isTrue);
    });
  });

  group('the sheet', () {
    testWidgets('a media row shows exactly ONE animation view, asks for its file once, and no drawing', (t) async {
      final repo = await _openSheet(t, _mediaOnly);
      expect(find.byType(ExerciseAnimationView), findsOneWidget);
      expect(find.byType(SvgPicture), findsNothing);
      expect(find.text('START'), findsNothing);
      expect(find.text('END'), findsNothing);
      expect(repo.ensured, [_mediaOnlyMedia.objectName], reason: 'the file is asked for when the sheet opens, not before');
    });

    testWidgets('a plate-only pair still shows START and END and never builds the animation view', (t) async {
      final repo = await _openSheet(t, 'Barbell Bench Press');
      expect(find.byType(ExerciseAnimationView), findsNothing);
      expect(find.byType(SvgPicture), findsNWidgets(2));
      expect(find.text('START'), findsOneWidget);
      expect(find.text('END'), findsOneWidget);
      expect(repo.ensured, isEmpty);
    });

    testWidgets('disable_exercise_plates: show() returns without opening the sheet', (t) async {
      await t.runAsync(_ensureHive);
      await _setFlag(t, 'disable_exercise_plates');
      final repo = await _openSheet(t, _mediaOnly);
      expect(find.byType(ExercisePlateSheet), findsNothing);
      expect(find.byType(ExerciseAnimationView), findsNothing);
      expect(repo.ensured, isEmpty);
    });

    testWidgets('disable_exercise_animations: a media AND plate row shows today\'s START and END, with zero animation views', (t) async {
      await t.runAsync(_ensureHive);
      await _setFlag(t, 'disable_exercise_animations');
      final repo = await _openSheet(t, _both);
      expect(find.byType(ExerciseAnimationView), findsNothing);
      expect(find.byType(SvgPicture), findsNWidgets(2));
      expect(find.text('START'), findsOneWidget);
      expect(find.text('END'), findsOneWidget);
      expect(repo.ensured, isEmpty);
    });

    testWidgets('disable_exercise_animations: a media-only row shows the existing no-drawing branch, with zero animation views', (t) async {
      await t.runAsync(_ensureHive);
      await _setFlag(t, 'disable_exercise_animations');
      final repo = await _openSheet(t, _mediaOnly);
      expect(find.byType(ExerciseAnimationView), findsNothing);
      expect(find.text('NO DRAWING YET'), findsOneWidget);
      expect(find.byType(ExerciseMonogram), findsOneWidget);
      expect(repo.ensured, isEmpty);
    });

    testWidgets('[o] the view\'s size equals the measured frame width, at a 390 px and at a 700 px wide sheet', (t) async {
      final widths = <double>[];
      for (final w in [390.0, 700.0]) {
        await _openSheet(t, _mediaOnly, surface: Size(w, 900));
        final view = t.widget<ExerciseAnimationView>(find.byType(ExerciseAnimationView));
        final frame = t.getSize(find.ancestor(of: find.byType(ExerciseAnimationView), matching: find.byType(AspectRatio)).first);
        expect(view.size, closeTo(frame.width, 0.01), reason: 'surface $w');
        expect(frame.height, closeTo(frame.width, 0.01), reason: 'the frame is square');
        expect(frame.width, greaterThan(300), reason: 'surface $w');
        widths.add(frame.width);
        await t.pumpWidget(const SizedBox());
      }
      expect(widths[1], greaterThan(widths[0]), reason: 'a wider sheet gets a wider frame, so a fixed size cannot pass both');
    });
  });
}
