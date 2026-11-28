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

Future<void> _pump(WidgetTester tester, List<Map<String, dynamic>> exercises,
    {List<Map<String, dynamic>>? library}) async {
  await ensureHive(tester);
  await seedLibrary(tester, rows: library ?? _library);
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

Map<String, dynamic> _gear(String id, String name, List<String> equipment,
        {String? source, List<String>? aliases}) =>
    <String, dynamic>{
      'id': id,
      'name': name,
      'category': 'Push',
      'logging_type': 'weight_reps',
      'equipment_needed': equipment,
      'source': ?source,
      'name_aliases': ?aliases,
    };

/// A bodyweight user, one own exercise ('Twin Test'), and the search sheet open.
Future<void> _openAsBodyweight(
    WidgetTester tester, List<Map<String, dynamic>> library) async {
  await _pump(tester, const [], library: library);
  await tester.runAsync(() async {
    await HiveService.instance.userBox
        .put('profile', <String, dynamic>{'equipment_access': 'bodyweight'});
    await HiveService.instance.customBox.put(
        'custom_exercise_twin', <String, dynamic>{
      'id': 'custom_exercise_twin',
      'name': 'Twin Test',
      'type': 'exercise',
      'category': 'Push',
      'logging_type': 'weight_reps',
      'equipment_needed': <String>[],
    });
  });
  await _openSearch(tester);
}

int _rowCount(WidgetTester tester) => (tester
        .widget<ListView>(_inSheet(find.byType(ListView)))
        .childrenDelegate as SliverChildBuilderDelegate)
    .childCount!;

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

    testWidgets(
        'search ignores curly apostrophes and extra spaces, for the list and own exercises',
        (tester) async {
      await _pump(tester, [
        {'exercise_name': _bench, 'sets': 3, 'reps': '8'},
      ]);
      await tester.runAsync(() => HiveService.instance.customBox.put(
          'custom_exercise_zed', <String, dynamic>{
        'id': 'custom_exercise_zed',
        'name': "Zed's Row",
        'type': 'exercise',
        'logging_type': 'weight_reps',
      }));
      await _openSearch(tester);
      final quote = String.fromCharCode(0x2019);
      final search = _inSheet(find.byType(TextField)).first;

      await tester.enterText(search, 'seated  cable');
      await _settle(tester);
      expect(_inSheet(find.text(_row)), findsOneWidget);
      expect(_inSheet(find.text("Zed's Row")), findsNothing,
          reason: 'mirror: the search still narrows');

      await tester.enterText(search, 'zed${quote}s  row');
      await _settle(tester);
      expect(_inSheet(find.text("Zed's Row")), findsOneWidget);
      expect(_inSheet(find.text(_row)), findsNothing);
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

  // Founder 2026-11-28: a user adding by hand can pick ANY exercise. Their equipment only
  // orders the list, through PickerRows.
  group('every exercise is offered', () {
    // The harness keeps one Hive dir per file: the bodyweight profile must not leak.
    tearDown(() => HiveService.instance.userBox.delete('profile'));

    testWidgets('theirs first, then the rest, and one name once', (tester) async {
      await _openAsBodyweight(tester, [
        _gear('A0', 'Barbell Row Test', ['barbell']),
        _gear('L1', 'Floor Press Test', ['bodyweight']),
        _gear('Z1', 'Twin Test', ['bodyweight'],
            source: 'community', aliases: ['Old Twin Name']),
      ]);
      double top(String name) => tester.getTopLeft(_inSheet(find.text(name))).dy;
      expect(top('Floor Press Test'), lessThan(top('Barbell Row Test')));
      expect(top('Twin Test'), lessThan(top('Barbell Row Test')));
      expect(_inSheet(find.text('Twin Test')), findsOneWidget);

      // The own exercise answers to the name of the copy it stands for.
      await tester.enterText(
          _inSheet(find.byType(TextField)).first, 'old twin name');
      await _settle(tester);
      expect(_inSheet(find.text('Twin Test')), findsOneWidget);
      expect(_inSheet(find.text('Floor Press Test')), findsNothing);
    });

    testWidgets('a typed name is reachable behind 30 matching rows',
        (tester) async {
      await _openAsBodyweight(tester, [
        _gear('A0', 'Barbell Press', ['barbell']),
        for (var i = 0; i < 31; i++)
          _gear('P${100 + i}', 'Press $i', ['bodyweight']),
      ]);
      expect(_rowCount(tester), 31,
          reason: 'the untyped list stays 30 library rows plus the own one');

      await tester.enterText(_inSheet(find.byType(TextField)).first, 'press');
      await _settle(tester);
      final barbell = _inSheet(find.text('Barbell Press'));
      await tester.scrollUntilVisible(barbell, 300,
          scrollable: find
              .descendant(
                  of: _inSheet(find.byType(ListView)),
                  matching: find.byType(Scrollable))
              .first);
      await tester.pump();
      await tester.tap(barbell);
      await _settle(tester);
      expect(find.byType(BottomSheet), findsNothing);
      expect(_card('Barbell Press'), findsOneWidget);
    });
  });

  group('the writer refuses what no row controls', () {
    testWidgets('a custom created with a name already in the template: refused in the sheet',
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
      // Founder 2026-11-25 (A16): a name the exercise list holds is refused where the custom
      // is created. The sheet stays open with the message and nothing is stored.
      final message = find.text(WardroomCopy.customExerciseNameTakenTemplate
          .replaceAll('{exercise}', _bench));
      await pumpUntilRealIoDone(tester, () => message.evaluate().isNotEmpty,
          what: 'the duplicate-name refusal');
      await _settle(tester);

      expect(find.byType(CreateCustomExerciseSheet), findsOneWidget);
      expect(find.text('1 ADDED'), findsOneWidget,
          reason: 'still one row (the name also shows in the open sheets, so count the badge)');
      expect(
          HiveService.instance.customBox.values
              .whereType<Map>()
              .any((m) => m['name'] == _bench),
          isFalse);
      expect(
          find.text(WardroomCopy.templateAlreadyAddedTemplate
              .replaceAll('{exercise}', _bench)),
          findsNothing,
          reason: 'refused before it reaches the template');
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'a custom named like a template row that is in NO list: the builder refuses it and says so',
        (tester) async {
      // An old or coach-made template row whose name is in neither the library nor the
      // customs: the create is allowed, so the builder's one writer must refuse it.
      const oldRow = 'Zercher Hold';
      await _pump(tester, [
        {'exercise_name': oldRow, 'sets': 3, 'reps': '8'},
      ]);
      await _openSearch(tester);
      await tester.tap(_inSheet(find.textContaining('CUSTOM')).first);
      await _settle(tester);
      await tester.enterText(_inSheet(find.byType(TextField)).first, oldRow);
      await tester.pump();
      await tester.ensureVisible(_inSheet(find.text('SAVE')));
      await tester.pump();
      await tapWithRealIo(tester, _inSheet(find.text('SAVE')));
      final message = find.text(WardroomCopy.templateAlreadyAddedTemplate
          .replaceAll('{exercise}', oldRow));
      await pumpUntilRealIoDone(tester, () => message.evaluate().isNotEmpty,
          what: 'the builder refusal');
      await _settle(tester);

      expect(message, findsOneWidget);
      expect(find.text('1 ADDED'), findsOneWidget);
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
