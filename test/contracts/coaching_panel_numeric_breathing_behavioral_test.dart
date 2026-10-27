// The active-workout FORM & CUES panel suppresses a numeric breathing_cue —
// asserted through the rendered widget.
//
// Until Batch A (2026-10-22) this guard was covered only by a source-grep for
// its regex in coaching_content_panel.dart. The data repair removed every real
// numeric row, so the guard is driven here by a synthetic copy of Surya
// Namaskar that differs ONLY in breathing_cue, with the real row as its mirror.
// The plate sheet carries the same guard (exercise_plate_sheet_test).
//
// Harness traps copied from exercise_plate_sheet_test: Hive opens lazily inside
// runAsync, and the FIRST test primes every AppTypography style before any
// path_provider mock exists.
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/features/train/screens/active_workout/screen.dart'
    show CoachingContentPanel;

Directory? _tempDir;

Future<void> _ensureHive() async {
  if (_tempDir != null) return;
  final dir = await Directory.systemTemp.createTemp('coaching_panel');
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
  final surya = lib.firstWhere((e) => e['name'] == 'Surya Namaskar');
  await HiveService.instance.exerciseBox.putAll({
    'E_SURYA': surya,
    'TEST_NUMERIC_BREATHING': {
      ...surya,
      'id': 'TEST_NUMERIC_BREATHING',
      'name': 'Synthetic Numeric Breathing',
      'breathing_cue': '12',
    },
  });
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

  Future<void> openPanel(WidgetTester t, String name) async {
    await t.runAsync(_ensureHive);
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(child: CoachingContentPanel(exerciseName: name)),
      ),
    ));
    await t.tap(find.text('FORM & CUES'));
    await t.pump();
  }

  // FIRST and Hive-free: primes the font failure cache for every style the
  // panel renders before the path_provider mock exists.
  testWidgets('fonts primed', (t) async {
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(children: [
          Text('prime mono', style: AppTypography.mono),
          Text('prime monoXs', style: AppTypography.monoXs),
          Text('prime bodySm', style: AppTypography.bodySm),
        ]),
      ),
    ));
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text('prime mono'), findsOneWidget);
  });

  testWidgets('a NUMERIC breathing_cue is suppressed in the panel', (t) async {
    await openPanel(t, 'Synthetic Numeric Breathing');
    // Positive control: the row resolved and the panel expanded.
    expect(find.text('12 positions with coordinated breath'), findsOneWidget);
    expect(find.text('BREATHING'), findsNothing);
    expect(find.text('12'), findsNothing);
  });

  testWidgets("the mirror: Surya Namaskar's real breathing cue renders", (t) async {
    await openPanel(t, 'Surya Namaskar');
    expect(find.text('12 positions with coordinated breath'), findsOneWidget);
    expect(find.text('BREATHING'), findsOneWidget);
    expect(find.text('Breath synced with each movement'), findsOneWidget);
  });
}
