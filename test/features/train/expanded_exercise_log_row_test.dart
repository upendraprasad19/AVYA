// OI-371 (diagnose: docs/diagnoses/2026-10-21-expanded-row-name-truncation-*.md)
//
// The Train expanded day's logged-exercise row: the name wraps in full (no
// ellipsis, no line cap), the detail sits on its own line and wraps only
// after a dot (numbers and units are joined by U+00A0), the icon tracks the
// first line at large text, a PR row reads "Personal record" first, and the
// counts are plural-correct through the real Train screen.
//
// ORDER IS LOAD-BEARING (zero_set_completion_behavioral_test.dart): fonts
// render first with NO path_provider mock; Hive opens lazily in runAsync.
@Timeout(Duration(minutes: 3))
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/workout_write_service.dart';
import 'package:icanbefitter/core/services/write_result.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/core/utils/ist_date.dart';
import 'package:icanbefitter/features/auth/providers/auth_invalidation_provider.dart';
import 'package:icanbefitter/features/train/providers/train_provider.dart';
import 'package:icanbefitter/features/train/screens/train/screen.dart';

import '../../helpers/hive_test_setup.dart';

final nb = String.fromCharCode(0xA0);
String get benchDetail => '3${nb}sets$nb· 8${nb}reps$nb· 60.0${nb}kg';

const names = [
  'Barbell Overhead Press',
  'Thoracic Extension (Foam Roller)',
  'Single Arm Landmine Press With Rotation To Overhead Lockout X',
];

Future<void> renderFontsFirst(WidgetTester tester) async {
  await tester.pumpWidget(MaterialApp(
    home: Column(children: [
      Text('a', style: AppTypography.h1),
      Text('a', style: AppTypography.h2),
      Text('b', style: AppTypography.h3),
      Text('c', style: AppTypography.mono),
      Text('d', style: AppTypography.monoXs),
      Text('e', style: AppTypography.bodySm),
      Text('f', style: AppTypography.body),
      Text('g', style: AppTypography.numeric),
    ]),
  ));
}

Future<void> pumpRow(WidgetTester tester, String name, String detail,
    {bool isPr = false, double scale = 1.0}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(320, 800);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(
          size: const Size(320, 800), textScaler: TextScaler.linear(scale)),
      child: Scaffold(
        body: Padding(
          // The expanded day's own inset inside the Train week list.
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(children: [
            ExpandedExerciseLogRow(name: name, detail: detail, isPr: isPr),
          ]),
        ),
      ),
    ),
  ));
}

RenderParagraph paragraphOf(WidgetTester tester, String text) =>
    tester.renderObject<RenderParagraph>(find.text(text));

double lineHeight(RenderParagraph p) =>
    p.getFullHeightForCaret(const TextPosition(offset: 0));

/// True when every glyph of [sub] inside [p]'s text is on one line.
bool onOneLine(RenderParagraph p, String sub) {
  final text = p.text.toPlainText();
  final start = text.indexOf(sub);
  expect(start, isNot(-1), reason: '"$sub" not in "$text"');
  final boxes = p.getBoxesForSelection(
      TextSelection(baseOffset: start, extentOffset: start + sub.length));
  return boxes.map((b) => b.top.round()).toSet().length == 1;
}

void main() {
  testWidgets('fonts degrade before any Hive mock', renderFontsFirst);

  group('ExpandedExerciseLogRow at 320 dp', () {
    for (final scale in [1.0, 1.3, 2.0]) {
      for (final name in names) {
        testWidgets('"$name" at $scale: complete, wrapped, icon on the first '
            'line', (tester) async {
          await pumpRow(tester, name, benchDetail, isPr: true, scale: scale);
          expect(tester.takeException(), isNull, reason: 'no overflow');

          final nameP = paragraphOf(tester, name);
          expect(nameP.didExceedMaxLines, isFalse);
          expect(nameP.text.toPlainText(), name, reason: 'not shortened');
          expect(find.text(benchDetail), findsOneWidget);

          final nameRect = tester.getRect(find.text(name));
          final detailRect = tester.getRect(find.text(benchDetail));
          expect(detailRect.top, greaterThanOrEqualTo(nameRect.bottom),
              reason: 'the detail sits on its own line');

          final icon = tester.getRect(find.byIcon(Icons.emoji_events));
          expect((icon.top - nameRect.top).abs(), lessThanOrEqualTo(4));
          final firstLineCentre = nameRect.top + lineHeight(nameP) / 2;
          expect((icon.center.dy - firstLineCentre).abs(),
              lessThanOrEqualTo(3));
        });
      }
    }

    testWidgets('at 2.0 the detail wraps, after a dot, never inside a count',
        (tester) async {
      final detail = '12${nb}sets$nb· 12${nb}reps$nb· 102.5${nb}kg';
      await pumpRow(tester, names[2], detail, scale: 2.0);
      expect(tester.takeException(), isNull);
      final p = paragraphOf(tester, detail);
      expect(p.size.height, greaterThan(lineHeight(p) * 1.5),
          reason: 'the detail wraps at 2.0');
      expect(onOneLine(p, '12${nb}reps'), isTrue);
      expect(onOneLine(p, '12${nb}sets'), isTrue);
      expect(onOneLine(p, '102.5${nb}kg'), isTrue);
    });

    testWidgets('a short name and a short detail still take two lines',
        (tester) async {
      // Side by side (a Wrap or a Row) this pair fits one line at 320 dp,
      // so only a stacked layout puts the detail under the name.
      final detail = '1${nb}set';
      await pumpRow(tester, 'Squat', detail);
      expect(tester.takeException(), isNull);
      final nameRect = tester.getRect(find.text('Squat'));
      final detailRect = tester.getRect(find.text(detail));
      expect(detailRect.top, greaterThanOrEqualTo(nameRect.bottom),
          reason: 'the detail sits on its own line');
      expect(detailRect.left, nameRect.left, reason: 'aligned under the name');
    });

    testWidgets('a PR row reads Personal record, the name, the detail',
        (tester) async {
      final sem = tester.ensureSemantics();
      await pumpRow(tester, 'Bench Press', benchDetail, isPr: true);
      expect(
          tester.getSemantics(find.byType(ExpandedExerciseLogRow)),
          isSemantics(label: 'Personal record\nBench Press\n$benchDetail'));
      sem.dispose();
    });

    testWidgets('a non-PR row reads the name and the detail', (tester) async {
      final sem = tester.ensureSemantics();
      await pumpRow(tester, 'Bench Press', benchDetail);
      expect(tester.getSemantics(find.byType(ExpandedExerciseLogRow)),
          isSemantics(label: 'Bench Press\n$benchDetail'));
      sem.dispose();
    });
  });

  group('through the Train screen', () {
    Directory? dir;
    tearDownAll(() async {
      if (dir != null) await tearDownHiveForTests(dir!);
    });

    testWidgets('1 set / 3 sets, 1 rep / 8 reps, weight, reps-only, timed '
        'and cardio branches', (tester) async {
      dir ??= await tester.runAsync(setUpHiveForTests);
      await tester.runAsync(() async {
        final wb = HiveService.instance.workoutBox;
        await wb.clear();
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        final monday = today.subtract(Duration(days: today.weekday - 1));
        await HiveService.instance.userBox
            .put('plan_start_date', istDateStr(monday));
        await wb.put('current_plan', {'focus': 'Test', 'name': 'Foundation'});
        for (int i = 0; i < 7; i++) {
          final d = monday.add(Duration(days: i));
          final isToday = istDateStr(d) == istDateStr(today);
          await wb.put('schedule_${istDateStr(d)}', {
            'date': istDateStr(d),
            'week': 1,
            'day_of_week': i,
            'type': isToday ? 'workout' : 'rest',
            'workout_name': isToday ? 'Push Day' : 'Rest Day',
            'workout_focus': 'Push',
            'status': 'planned',
            'exercises': <Map<String, dynamic>>[],
          });
        }
        final logs = <(String, double, int, int)>[
          ('Bench Press', 60, 8, 3), // weight, plural
          ('Overhead Press', 40, 1, 1), // weight, singular
          ('Push-up', 0, 12, 3), // reps-only, plural
          ('Dip', 0, 1, 1), // reps-only, singular
        ];
        for (final (name, kg, reps, sets) in logs) {
          final res = await WorkoutWriteService.instance.logExercise(
            date: now,
            exerciseName: name,
            sets: [
              for (var i = 0; i < sets; i++)
                ExerciseSet(
                    weightKg: kg,
                    reps: reps,
                    loggedAtMs: now.millisecondsSinceEpoch - 6000 + i),
            ],
            source: WriteSource.activeWorkout,
          );
          expect(res.success, isTrue, reason: res.errorMessage);
        }
        // B-pass fb5048e68fae F10: the timed and cardio detail builders.
        // A custom name with durations and no weight resolves to timed; the
        // cardio type comes from the library row.
        await HiveService.instance.exerciseBox.put('test_rowing_erg',
            {'name': 'Rowing Erg', 'logging_type': 'cardio'});
        for (final (name, secs, sets) in [
          ('Plank Hold', 45, 3),
          ('Rowing Erg', 1200, 1),
        ]) {
          final res = await WorkoutWriteService.instance.logExercise(
            date: now,
            exerciseName: name,
            sets: [
              for (var i = 0; i < sets; i++)
                ExerciseSet(
                    weightKg: 0,
                    reps: 0,
                    durationSec: secs,
                    loggedAtMs: now.millisecondsSinceEpoch - 3000 + i),
            ],
            source: WriteSource.activeWorkout,
          );
          expect(res.success, isTrue, reason: res.errorMessage);
        }
        final marked = await WorkoutWriteService.instance
            .markCompleted(date: now, workoutName: 'Push Day', durationSec: 60);
        expect(marked.success, isTrue);
      });

      final c = ProviderContainer(
          overrides: [authUserIdTokenProvider.overrideWithValue('u')]);
      addTearDown(c.dispose);
      await tester.pumpWidget(UncontrolledProviderScope(
          container: c, child: const MaterialApp(home: TrainScreen())));
      await tester.pump();
      await tester.pump();
      c.read(expandedDayProvider.notifier).toggle(DateTime.now().weekday - 1);
      await tester.pump();

      expect(find.text('3${nb}sets$nb· 8${nb}reps$nb· 60.0${nb}kg'),
          findsOneWidget);
      expect(find.text('1${nb}set$nb· 1${nb}rep$nb· 40.0${nb}kg'),
          findsOneWidget);
      expect(find.text('3${nb}sets$nb· 12${nb}reps'), findsOneWidget);
      expect(find.text('1${nb}set$nb· 1${nb}rep'), findsOneWidget);
      expect(find.text('3${nb}sets$nb· best 45s'), findsOneWidget);
      // The cardio minutes are not asserted: logExercise zeroes durationSec
      // for every non-timed type (workout_write_service.dart
      // _normalizeSetsByLoggingType), filed separately; this pins the format.
      final cardio = tester
          .widgetList<ExpandedExerciseLogRow>(find.byType(ExpandedExerciseLogRow))
          .singleWhere((r) => r.name == 'Rowing Erg');
      expect(cardio.detail, matches(RegExp('^\\d+${nb}min$nb· \\d+\\.\\d${nb}km\$')));
      expect(find.byType(ExpandedExerciseLogRow), findsNWidgets(6));

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    });
  });
}
