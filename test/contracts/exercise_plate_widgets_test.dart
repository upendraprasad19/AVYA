// test/contracts/exercise_plate_widgets_test.dart
//
// ⚠ HIVE IS OPENED LAZILY, NOT IN setUpAll, AND THE ORDER OF THESE TESTS IS
// LOAD-BEARING. The repo bundles no fonts (pubspec declares no `fonts:` section
// and there is no .ttf in the tree), so GoogleFonts always fails inside the
// harness and AppTypography degrades to a fallback face — which is fine for
// what these tests assert. But this file mocks the `path_provider` channel so
// Hive can open a box, and GoogleFonts SAVES fetched fonts through that same
// channel (`_httpFetchFontAndSaveToDevice`). Answering it walks GoogleFonts
// into the fetch-and-save path, where the network failure surfaces as a test
// error on whichever test renders an AppTypography style FIRST — the failure
// follows POSITION, not content, and moves to whatever test is at the top.
//
// Proven by probe: the identical monogram assertions pass with no Hive setUpAll
// at all. So the first tests below open no box, which lets GoogleFonts fail and
// cache the failure the ordinary way before any mock is installed.
//
// Tried and rejected for the FONT problem, so nobody re-spends the time:
// allowRuntimeFetching=false (turns a soft degrade into a hard throw), the
// wardroom goldens' warmup loop, takeException (the error arrives after the
// body), FlutterError.onError suppression (it is not routed there), priming the
// families directly, and seeding fewer rows (it is the box open, not the row
// count).
//
// The second half of the fix is `runAsync`: _ensureHive does real disk I/O, and
// a testWidgets body runs in a FAKE-ASYNC zone where that never completes. The
// first attempt awaited it directly and the file reported "did not complete"
// after 4m55s. Any real I/O reached from a test body needs the same wrapper.
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/shared/widgets/exercise_plate/exercise_monogram.dart';
import 'package:icanbefitter/shared/widgets/exercise_plate/exercise_plate_thumb.dart';
import 'package:icanbefitter/shared/widgets/exercise_plate/plate_flags.dart';

Widget _host(Widget child) =>
    MaterialApp(home: Scaffold(body: Center(child: child)));

Directory? _tempDir;

/// Opens Hive on first call and seeds the library. Idempotent, and deliberately
/// NOT a setUpAll — see the file header.
Future<void> _ensureHive() async {
  if (_tempDir != null) return;
  final dir = await Directory.systemTemp.createTemp('plate_widgets');
  _tempDir = dir;
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (_) async => dir.path,
  );
  Hive.init(dir.path);
  await HiveService.instance.init();
  final lib =
      (jsonDecode(File('assets/data/exercise_library.json').readAsStringSync())
              as List)
          .cast<Map<String, dynamic>>();
  await HiveService.instance.exerciseBox
      .putAll({for (final e in lib) e['id'] as String: e});
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

  // ---- FIRST, and Hive-free by design (see the file header). ----
  testWidgets('the monogram renders initials, never a broken image', (t) async {
    await t.pumpWidget(
        _host(const ExerciseMonogram(name: 'Barbell Bench Press', size: 44)));
    expect(find.text('BBP'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('the monogram honours its size', (t) async {
    await t.pumpWidget(_host(const ExerciseMonogram(name: 'Wall Sit', size: 44)));
    final box = t.widget<SizedBox>(find
        .descendant(
            of: find.byType(ExerciseMonogram), matching: find.byType(SizedBox))
        .first);
    expect(box.width, 44);
    expect(box.height, 44);
  });

  // ---- from here on the thumb needs the library in Hive ----
  testWidgets('the thumb falls back to the monogram when there is no artwork',
      (t) async {
    await t.runAsync(_ensureHive);
    await t.pumpWidget(_host(const ExercisePlateThumb(
        exerciseName: 'Totally Invented Exercise', size: 44)));
    await t.pump();
    expect(find.byType(ExerciseMonogram), findsOneWidget);
  });

  testWidgets('the thumb exposes a 44 px tap target that fires', (t) async {
    await t.runAsync(_ensureHive);
    var tapped = false;
    await t.pumpWidget(_host(ExercisePlateThumb(
        exerciseName: 'Totally Invented Exercise',
        size: 44,
        onTap: () => tapped = true)));
    await t.pump();
    final size = t.getSize(find.byType(ExercisePlateThumb));
    expect(size.width, greaterThanOrEqualTo(44));
    expect(size.height, greaterThanOrEqualTo(44));
    await t.tap(find.byType(ExercisePlateThumb));
    expect(tapped, isTrue);
  });

  testWidgets('the thumb RE-RESOLVES when the exercise name changes', (t) async {
    await t.runAsync(_ensureHive);
    // The names must sit on OPPOSITE sides of hasArtwork. Two artwork-less
    // names would both render ExerciseMonogram(name: widget.exerciseName),
    // which reads the WIDGET not the resolved plate — so deleting
    // didUpdateWidget entirely would still pass.
    await t.pumpWidget(
        _host(const ExercisePlateThumb(exerciseName: 'Wall Sit', size: 44)));
    await t.pump();
    await t.pump(const Duration(milliseconds: 100));
    expect(find.byType(SvgPicture), findsOneWidget, reason: 'Wall Sit has art');

    await t.pumpWidget(_host(const ExercisePlateThumb(
        exerciseName: 'Totally Invented Exercise', size: 44)));
    await t.pump();
    await t.pump(const Duration(milliseconds: 100));
    expect(find.byType(SvgPicture), findsNothing,
        reason: 'a swap reuses the State; didUpdateWidget must re-resolve');
    expect(find.byType(ExerciseMonogram), findsOneWidget);
  });

  // ---- the kill switch (platform tier's `feature_flag` requirement) ----
  testWidgets('the kill switch stops the plate loading its asset', (t) async {
    await t.runAsync(_ensureHive);
    // Guarantee the flag is cleared even if an expect below throws. The manual
    // delete at the end of the body only runs on the happy path, which would
    // leak `disable_exercise_plates` into every later test in this file.
    addTearDown(() async => HiveService.instance.configBox
        .delete('disable_exercise_plates'));

    // ON by default — establish the positive half, or the assertion below
    // would pass on a thumb that never rendered a plate for any reason.
    expect(PlateFlags.platesEnabled, isTrue);
    await t.pumpWidget(
        _host(const ExercisePlateThumb(exerciseName: 'Wall Sit', size: 44)));
    await t.pump();
    await t.pump(const Duration(milliseconds: 100));
    expect(find.byType(SvgPicture), findsOneWidget,
        reason: 'precondition: Wall Sit has artwork and plates are enabled');

    await t.runAsync(() async => HiveService.instance.configBox
        .put('disable_exercise_plates', true));
    expect(PlateFlags.platesEnabled, isFalse);

    await t.pumpWidget(
        _host(const ExercisePlateThumb(exerciseName: 'Wall Sit', size: 44)));
    await t.pump();
    await t.pump(const Duration(milliseconds: 100));
    expect(find.byType(SvgPicture), findsNothing,
        reason: 'the kill switch must stop the asset load, not just hide it');
    expect(find.byType(ExerciseMonogram), findsOneWidget,
        reason: 'it falls back to the monogram, so layout is unchanged');

    await t.runAsync(
        () async => HiveService.instance.configBox.delete('disable_exercise_plates'));
    expect(PlateFlags.platesEnabled, isTrue,
        reason: 'restored for later tests (addTearDown is the belt-and-braces)');
  });

  // PRESENCE ONLY, and said out loud rather than dressed up as behavioural.
  //
  // The errorBuilder path needs SvgPicture.asset to fail. Both ways of causing
  // that fight the harness: a genuinely absent asset leaves the loader with work
  // outstanding and the test reports "did not complete" after 6m35s, and a
  // stubbed DefaultAssetBundle throws through flutter_svg's own loader before
  // the errorBuilder is consulted, recursing ~1000 frames.
  //
  // The path is also unreachable in production today — it needs a community row
  // carrying demo_slug, and user_custom_exercises has no such column. The guard
  // is cheap insurance for the day it does. So: pin that it EXISTS and returns
  // the monogram, and be explicit that nothing here proves it runs.
  test('the thumb declares an errorBuilder that falls back to the monogram', () {
    final src =
        File('lib/shared/widgets/exercise_plate/exercise_plate_thumb.dart')
            .readAsStringSync()
            .replaceAll(RegExp(r'//.*'), '');
    expect(src.contains('errorBuilder:'), isTrue,
        reason: 'an unbundled slug would render a raw error box');
    final i = src.indexOf('errorBuilder:');
    expect(src.substring(i, i + 160).contains('ExerciseMonogram'), isTrue,
        reason: 'errorBuilder does not fall back to the monogram');
  });
}
