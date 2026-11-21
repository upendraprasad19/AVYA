// Batch M2b Part B: ONE parser for the four coaching fields of an exercise row
// (`exerciseCuesOf`), shared by the FORM & CUES panel, the plate sheet and the
// logging viewer. SoT concept `exercise_coaching_content`.
//
// Before this batch the panel and the sheet each parsed the row themselves: the
// sheet split `coaching_cues` on ';', the panel did not (no bundled row has a
// ';' in a cue or mistake item, 914 rows, pinned by
// exercise_library_text_shape_contract_test), and each carried its own copy of
// the numeric-breathing guard. `breathing_cue` (37 rows) and `warmup_protocol`
// (3 rows) DO contain ';' and are never split.
//
// Harness traps copied from coaching_panel_numeric_breathing_behavioral_test:
// Hive opens lazily inside runAsync, and the FIRST test primes every
// AppTypography style before any path_provider mock exists.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/features/train/screens/active_workout/screen.dart'
    show CoachingContentPanel;
import 'package:icanbefitter/shared/widgets/exercise_plate/exercise_cues.dart';
import 'package:icanbefitter/shared/widgets/exercise_plate/exercise_plate_sheet.dart';

const _semicolonRow = 'Synthetic Semicolon Cues';

Directory? _tempDir;

Future<void> _ensureHive() async {
  if (_tempDir != null) return;
  final dir = await Directory.systemTemp.createTemp('exercise_cues');
  _tempDir = dir;
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (_) async => dir.path,
  );
  Hive.init(dir.path);
  await HiveService.instance.init();
  // A row that packs a cue with ';' (an install still on an older seed, or a
  // community row) next to ';' inside breathing_cue.
  await HiveService.instance.exerciseBox.put('TEST_SEMICOLON_CUES', {
    'id': 'TEST_SEMICOLON_CUES',
    'name': _semicolonRow,
    'coaching_cues': ['Brace the core; keep the ribs down', 'Chest up'],
    'common_mistakes': ['Flared elbows'],
    'breathing_cue': 'Exhale up; inhale down',
    'warmup_protocol': '',
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

  // FIRST and Hive-free: primes the font failure cache for every style the
  // panel and the sheet render before the path_provider mock exists.
  testWidgets('fonts primed', (t) async {
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(children: [
          Text('prime mono', style: AppTypography.mono),
          Text('prime monoXs', style: AppTypography.monoXs),
          Text('prime bodySm', style: AppTypography.bodySm),
          Text('prime body', style: AppTypography.body),
        ]),
      ),
    ));
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text('prime mono'), findsOneWidget);
  });

  group('exerciseCuesOf (pure)', () {
    test('cues split on ; and are trimmed; blanks dropped', () {
      final c = exerciseCuesOf({
        'coaching_cues': ['Brace; keep ribs down', ' Chest up ', '  ', ';'],
      });
      expect(c.cues, ['Brace', 'keep ribs down', 'Chest up']);
    });

    test('mistakes are trimmed strings, non-strings coerced, blanks dropped', () {
      final c = exerciseCuesOf({
        'common_mistakes': ['Flared elbows', 5, '', '  '],
      });
      expect(c.mistakes, ['Flared elbows', '5']);
    });

    test('a ; inside a mistake is NOT split (only cues split)', () {
      final c = exerciseCuesOf({
        'common_mistakes': ['Bouncing; rushing the rep'],
      });
      expect(c.mistakes, ['Bouncing; rushing the rep']);
    });

    test('a numeric breathing_cue is the fingerprint of a column shift: dropped',
        () {
      expect(exerciseCuesOf({'breathing_cue': '5'}).breathing, isNull);
      expect(exerciseCuesOf({'breathing_cue': ' 5.5 '}).breathing, isNull);
      expect(exerciseCuesOf({'breathing_cue': '12'}).breathing, isNull);
    });

    test('a text breathing_cue is kept, and its ; is never split', () {
      expect(exerciseCuesOf({'breathing_cue': '4 s in, 4 s out'}).breathing,
          '4 s in, 4 s out');
      expect(exerciseCuesOf({'breathing_cue': 'Exhale up; inhale down'}).breathing,
          'Exhale up; inhale down');
    });

    test('warm-up: empty and whitespace dropped, ; kept whole', () {
      expect(exerciseCuesOf({'warmup_protocol': ''}).warmup, isNull);
      expect(exerciseCuesOf({'warmup_protocol': '   '}).warmup, isNull);
      expect(exerciseCuesOf({'warmup_protocol': '2 light sets; then 1 feeler'})
          .warmup, '2 light sets; then 1 feeler');
    });

    test('community rows carry arbitrary JSON types: tolerated, never thrown',
        () {
      final c = exerciseCuesOf({
        'coaching_cues': 'not a list',
        'common_mistakes': {'a': 1},
        'breathing_cue': 5,
        'warmup_protocol': ['x'],
      });
      expect(c.cues, isEmpty);
      expect(c.mistakes, isEmpty);
      expect(c.breathing, isNull);
      expect(c.warmup, isNull);
    });

    test('a null row (no library match) is all empty', () {
      final c = exerciseCuesOf(null);
      expect(c.cues, isEmpty);
      expect(c.mistakes, isEmpty);
      expect(c.breathing, isNull);
      expect(c.warmup, isNull);
    });
  });

  group('one parser, three readers: the panel and the sheet render the same '
      'lines from the same row', () {
    Future<void> openPanel(WidgetTester t) async {
      await t.runAsync(_ensureHive);
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
              child: CoachingContentPanel(exerciseName: _semicolonRow)),
        ),
      ));
      await t.tap(find.text('FORM & CUES'));
      await t.pump();
    }

    Future<void> openSheet(WidgetTester t) async {
      await t.runAsync(_ensureHive);
      await t.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: ExercisePlateSheet(exerciseName: _semicolonRow),
        ),
      ));
      await t.pump();
    }

    testWidgets('a row with no cues renders no panel at all, not a bare heading',
        (t) async {
      await t.runAsync(_ensureHive);
      await t.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
              child: CoachingContentPanel(exerciseName: 'No Such Exercise')),
        ),
      ));
      await t.pump();
      expect(find.text('FORM & CUES'), findsNothing);
      expect(find.byType(CoachingContentPanel), findsOneWidget);
      expect(t.getSize(find.byType(CoachingContentPanel)), Size.zero);
    });

    testWidgets('the panel splits a ;-packed cue like the sheet always did',
        (t) async {
      await openPanel(t);
      expect(find.text('Brace the core'), findsOneWidget);
      expect(find.text('keep the ribs down'), findsOneWidget);
      expect(find.text('Chest up'), findsOneWidget);
      expect(find.text('Brace the core; keep the ribs down'), findsNothing);
      expect(find.text('Exhale up; inhale down'), findsOneWidget,
          reason: 'breathing is never split');
    });

    testWidgets('the sheet renders the identical cue lines', (t) async {
      await openSheet(t);
      expect(find.text('Brace the core'), findsOneWidget);
      expect(find.text('keep the ribs down'), findsOneWidget);
      expect(find.text('Chest up'), findsOneWidget);
      expect(find.text('Exhale up; inhale down'), findsOneWidget);
    });
  });
}
