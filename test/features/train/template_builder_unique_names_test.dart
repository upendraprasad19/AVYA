// SoT concept `exercise_name_unique_in_day` (OI-358): the REAL template builder.
// A template holding a name twice reaches the Active Workout screen on the day it
// is scheduled, so the builder's one writer refuses it and its search sheet greys
// the row. Also pins the display half of the batch: a row keeps its name and
// numbers whichever shape it came in (`createTemplate` writes `exercise_name`,
// `sets`, `reps`; on `main` the card read only `name` and `prescribed_*`).
@Timeout(Duration(minutes: 3))
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/copy/wardroom_copy.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/features/train/screens/template_builder_screen.dart';
import 'package:icanbefitter/features/train/widgets/create_custom_exercise_sheet.dart';

import 'log_exercise/card_harness.dart';

const _bench = 'Barbell Bench Press';
const _row = 'Seated Cable Row';

final _library = <Map<String, dynamic>>[
  {'id': 'E1', 'name': _bench, 'category': 'Push', 'logging_type': 'weight_reps'},
  {'id': 'E2', 'name': _row, 'category': 'Pull', 'logging_type': 'weight_reps'},
];

Future<void> _pump(WidgetTester tester, List<Map<String, dynamic>> exercises) async {
  await ensureHive(tester);
  await seedLibrary(tester, rows: _library);
  await tester.runAsync(() => HiveService.instance.customBox.clear());
  await tester.pumpWidget(ProviderScope(
    child: MaterialApp(
      home: TemplateBuilderScreen(editData: {
        'templateId': 'tmpl_t1',
        'templateData': {'name': 'Saved', 'exercises': exercises},
      }),
    ),
  ));
  await tester.pump();
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Finder _inSheet(Finder f) =>
    find.descendant(of: find.byType(BottomSheet).last, matching: f);

Future<void> _openSearch(WidgetTester tester) async {
  final add = find.text('+ ADD EXERCISE').last;
  await tester.ensureVisible(add);
  await tester.pump();
  await tester.tap(add);
  await _settle(tester);
}

Finder _card(String name) => find.text(name);

void main() {
  tearDownAll(closeHive);

  testWidgets('fonts degrade before any Hive mock', renderFontsFirst);

  group('search sheet', () {
    testWidgets('a name in the template is greyed, findable, and cannot be tapped',
        (tester) async {
      await _pump(tester, [
        {'exercise_name': _bench, 'sets': 3, 'reps': '8'},
      ]);
      await _openSearch(tester);
      expect(_inSheet(find.text(_bench)), findsOneWidget);
      expect(_inSheet(find.text(WardroomCopy.templateAlreadyAddedTag)),
          findsOneWidget);

      await tester.tap(_inSheet(find.text(_bench)));
      await _settle(tester);
      expect(find.byType(BottomSheet), findsOneWidget, reason: 'nothing happened');
    });

    testWidgets('a new name adds to the template', (tester) async {
      await _pump(tester, [
        {'exercise_name': _bench, 'sets': 3, 'reps': '8'},
      ]);
      await _openSearch(tester);
      await tester.tap(_inSheet(find.text(_row)));
      await _settle(tester);
      expect(find.byType(BottomSheet), findsNothing);
      expect(_card(_row), findsOneWidget);
    });
  });

  group('the writer refuses what no row controls', () {
    testWidgets('a custom created with a name already in the template',
        (tester) async {
      await _pump(tester, [
        {'exercise_name': _bench, 'sets': 3, 'reps': '8'},
      ]);
      await _openSearch(tester);
      await tester.tap(_inSheet(find.textContaining('CUSTOM')).first);
      await _settle(tester);
      await tester.enterText(_inSheet(find.byType(TextField)).first, _bench);
      await tester.pump();
      await tester.ensureVisible(_inSheet(find.text('SAVE')));
      await tester.pump();
      await tapWithRealIo(tester, _inSheet(find.text('SAVE')));
      // The sheet closes, and onCreated runs, only after the real write.
      final sheet = find.byType(CreateCustomExerciseSheet);
      await pumpUntilRealIoDone(tester, () => sheet.evaluate().isEmpty,
          what: 'saving the custom exercise');
      await _settle(tester);

      expect(_card(_bench), findsOneWidget, reason: 'still one row');
      expect(
          find.text(WardroomCopy.templateAlreadyAddedTemplate
              .replaceAll('{exercise}', _bench)),
          findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('a template that already holds a name twice', () {
    // Restore is how this reaches a template (diagnose b3c8d2): no picker saw it.
    final twice = <Map<String, dynamic>>[
      {'exercise_name': _bench, 'sets': 3, 'reps': '8'},
      {'exercise_name': ' barbell bench PRESS ', 'sets': 5, 'reps': '5'},
      {'exercise_name': _row, 'sets': 3, 'reps': '10'},
      {'sets': 2, 'reps': '12'},
      {'sets': 2, 'reps': '15'},
    ];

    testWidgets('opens with the first of each name and keeps every nameless row',
        (tester) async {
      await _pump(tester, twice);
      expect(find.text('4 ADDED'), findsOneWidget);
      expect(_card(_bench), findsOneWidget);
      expect(find.textContaining('3 sets x 8'), findsOneWidget);
      expect(find.textContaining('5 sets x 5'), findsNothing,
          reason: 'the first row stays, not the later one');
      expect(_card(_row), findsOneWidget);
      expect(find.text('Unknown'), findsNWidgets(2), reason: 'never dropped');
      expect(tester.takeException(), isNull);
    });

    testWidgets('Save writes the distinct rows back to the stored template',
        (tester) async {
      await _pump(tester, twice);
      await tester.runAsync(() => HiveService.instance.workoutBox.put('tmpl_t1', {
            'id': 'tmpl_t1',
            'type': 'template',
            'name': 'Before the save',
            'exercises': twice,
            'exercise_count': twice.length,
          }));

      await tapWithRealIo(tester, find.text('SAVE'));
      final saveButton = find.widgetWithText(TextButton, 'SAVE');
      await pumpUntilRealIoDone(tester, () {
        final row = HiveService.instance.workoutBox.get('tmpl_t1') as Map;
        return row['name'] == 'Saved' &&
            (saveButton.evaluate().isEmpty ||
                tester.widget<TextButton>(saveButton).onPressed != null);
      }, what: 'saving the template');
      await _settle(tester);

      final stored = HiveService.instance.workoutBox.get('tmpl_t1') as Map;
      final names = [
        for (final row in stored['exercises'] as List)
          (row as Map)['exercise_name'],
      ];
      expect(names, [_bench, _row, null, null]);
      expect(stored['exercise_count'], 4);
    });
  });

  group('a row keeps its name and numbers in any shape', () {
    testWidgets('createTemplate shape: exercise_name, sets, reps', (tester) async {
      await _pump(tester, [
        {'exercise_id': 'E1', 'exercise_name': _bench, 'sets': 4, 'reps': '6'},
      ]);
      expect(find.text(_bench), findsOneWidget);
      expect(find.text('Unknown'), findsNothing);
      expect(find.textContaining('4 sets x 6'), findsOneWidget);
    });

    testWidgets('a String sets parses instead of throwing', (tester) async {
      await _pump(tester, [
        {'exercise_name': _bench, 'sets': '5', 'reps': 12},
      ]);
      expect(tester.takeException(), isNull);
      expect(find.textContaining('5 sets x 12'), findsOneWidget);
    });

    testWidgets('a picked library row still reads its defaults', (tester) async {
      await _pump(tester, [
        {'name': _row, 'default_sets': 2, 'default_reps': '15'},
      ]);
      expect(find.text(_row), findsOneWidget);
      expect(find.textContaining('2 sets x 15'), findsOneWidget);
    });
  });
}
