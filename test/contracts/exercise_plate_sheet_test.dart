// test/contracts/exercise_plate_sheet_test.dart
//
// The shape rule asserted through the RENDERED widget — a resolver unit test
// passes even if the sheet ignores isPair.
//
// ⚠ Two harness traps, both documented at length in
// test/contracts/exercise_plate_widgets_test.dart and reproduced in shape here:
//  1. Hive is opened LAZILY inside runAsync, never in setUpAll. A testWidgets
//     body is a fake-async zone where real disk I/O never completes.
//  2. The FIRST test renders an AppTypography style with NO path_provider mock
//     installed, so GoogleFonts fails and caches the failure the ordinary way.
//     Once the mock is up, GoogleFonts follows it into its fetch-and-save path
//     and the network failure surfaces as a test error instead.
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/shared/widgets/exercise_plate/exercise_monogram.dart';
import 'package:icanbefitter/shared/widgets/exercise_plate/exercise_plate_sheet.dart';

Directory? _tempDir;

Future<void> _ensureHive() async {
  if (_tempDir != null) return;
  final dir = await Directory.systemTemp.createTemp('plate_sheet');
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

List<Map<String, dynamic>> _library() =>
    (jsonDecode(File('assets/data/exercise_library.json').readAsStringSync())
            as List)
        .cast<Map<String, dynamic>>();

int _cueLines(Map<String, dynamic> e) => (e['coaching_cues'] as List)
    .expand((c) => c.toString().split(';'))
    .where((c) => c.trim().isNotEmpty)
    .length;

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

  Future<void> open(WidgetTester t, String name, {Size? surface}) async {
    await t.runAsync(_ensureHive);
    if (surface != null) {
      await t.binding.setSurfaceSize(surface);
      addTearDown(() => t.binding.setSurfaceSize(null));
    }
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (ctx) => TextButton(
            onPressed: () => ExercisePlateSheet.show(ctx, name),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await t.tap(find.text('open'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
  }

  // ---- FIRST, and Hive-free by design: this is the empty state the sheet
  // renders for the 127 exercises with no drawing, and it primes the font
  // failure cache before any path_provider mock exists. ----
  testWidgets('the no-drawing empty state renders at the sheet size', (t) async {
    // Renders EVERY AppTypography style the sheet uses, not just the monogram's.
    // GoogleFonts caches per family+weight, so priming JetBrains Mono alone
    // leaves DM Sans (the cue lines) to fail on whichever test renders it first.
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

  testWidgets('a pair shows TWO plates labelled START and END', (t) async {
    await open(t, 'Barbell Bench Press');
    expect(find.byType(SvgPicture), findsNWidgets(2));
    expect(find.text('START'), findsOneWidget);
    expect(find.text('END'), findsOneWidget);
  });

  testWidgets('a hold shows ONE plate and never says END', (t) async {
    await open(t, 'Wall Sit');
    expect(find.byType(SvgPicture), findsOneWidget);
    expect(find.text('END'), findsNothing);
    expect(find.text('HOLD THIS POSITION'), findsOneWidget);
  });

  testWidgets('no artwork shows the monogram, not a broken box', (t) async {
    await open(t, 'Surya Namaskar');
    expect(find.byType(SvgPicture), findsNothing);
    expect(find.text('NO DRAWING YET'), findsOneWidget);
  });

  testWidgets('a REAL breathing cue renders', (t) async {
    // Barbell Bench Press carries "Inhale down, exhale on press" (verified
    // against the library). Without this positive half, the suppression test
    // below would pass on a sheet that never renders BREATHING at all.
    await open(t, 'Barbell Bench Press');
    expect(find.text('BREATHING'), findsOneWidget);
  });

  testWidgets('a NUMERIC breathing_cue is suppressed', (t) async {
    // Surya Namaskar's breathing_cue is the string "12" — one of the 136 rows
    // where a spreadsheet column shift put met_value into the field (OI-149).
    await open(t, 'Surya Namaskar');
    expect(find.text('BREATHING'), findsNothing);
  });

  testWidgets('the sheet scrolls rather than overflowing at 320x480', (t) async {
    // The genuine worst case: an exercise WITH two plates (each AspectRatio 1)
    // AND the most cue lines. Picked from the data rather than by hand — the
    // first attempt named an exercise with no artwork at all, so it rendered
    // one monogram instead of two square plates and tested nothing.
    final worst = _library()
        .where((e) => e['demo_pair'] == true && e['coaching_cues'] is List)
        .reduce((a, b) => _cueLines(a) >= _cueLines(b) ? a : b);
    await open(t, worst['name'] as String, surface: const Size(320, 480));
    expect(t.takeException(), isNull, reason: 'RenderFlex overflow');
    expect(find.byType(SingleChildScrollView), findsWidgets);
  });
}
