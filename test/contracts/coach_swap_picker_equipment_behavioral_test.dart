// BEHAVIOURAL: which substitutes the AI coach's Swap picker offers.
//
// Founder 2026-11-28: a swap the user picks by hand ignores equipment, so EVERY exercise is
// offered; the ones the user's equipment covers come first. History below.
//
// Found 2026-11-26 while checking the OI-348 walk's picker rules: `_substitutesFor` passed
// `equipment_needed?.toString()` to the equipment rule. The library stores that field as a LIST,
// so the rule received the text "[dumbbells]", could not read it, and failed closed: every
// built-in exercise was hidden from every user with a profile. The sheet's two earlier tests
// seed a plain String (or no profile), so neither saw it.
//
// Reader: lib/features/ai_coach/widgets/swap_exercise_coach_sheet.dart `_substitutesFor`,
// through lib/shared/repositories/picker_rows.dart.
@Timeout(Duration(minutes: 3))
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/copy/wardroom_copy.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/utils/ist_date.dart';
import 'package:icanbefitter/features/ai_coach/widgets/swap_exercise_coach_sheet.dart';
import 'package:icanbefitter/shared/widgets/wardroom/ward_button.dart';

import '../features/train/log_exercise/card_harness.dart' show renderFontsFirst;
import '../helpers/hive_test_setup.dart';

const _planned = 'Planned Lift';

Future<void> _seed(String tier, {List<String> alsoPlanned = const []}) async {
  await HiveService.instance.userBox
      .put('profile', <String, dynamic>{'equipment_access': tier});
  await HiveService.instance.workoutBox.put(
      'schedule_${istDateStr(nowWall())}', <String, dynamic>{
    'date': istDateStr(nowWall()),
    'type': 'workout',
    'workout_name': 'D',
    'status': 'planned',
    'exercises': <Map<String, dynamic>>[
      {'exercise_id': 'ex_planned', 'exercise_name': _planned},
      for (final n in alsoPlanned) {'exercise_id': n, 'exercise_name': n},
    ],
  });
  // The library's real shape: `equipment_needed` is a LIST.
  // The barbell row sorts FIRST in Hive, so an order assertion cannot pass unless the
  // list really puts the user's equipment first.
  for (final (id, name, equipment) in <(String, String, List<String>)>[
    ('A0', 'Barbell Row Test', ['barbell']),
    ('L1', 'Floor Press Test', ['bodyweight']),
    ('L2', 'Dumbbell Press Test', ['dumbbells']),
    ('L4', 'Unlisted Gear Test', []),
  ]) {
    await HiveService.instance.exerciseBox.put(id, <String, dynamic>{
      'id': id,
      'name': name,
      'equipment_needed': equipment,
      if (id == 'L2') 'name_aliases': ['Old DB Push Test'],
    });
  }
  // A row with no equipment field at all.
  await HiveService.instance.exerciseBox
      .put('L5', <String, dynamic>{'id': 'L5', 'name': 'No Gear Field Test'});
  for (final (key, name, equipment) in <(String, String, List<String>)>[
    ('custom_exercise_1', 'Own Move Test', []),
    ('custom_exercise_2', 'Own Barbell Test', ['barbell']),
  ]) {
    await HiveService.instance.customBox.put(key, <String, dynamic>{
      'id': key,
      'type': 'exercise',
      'name': name,
      'equipment_needed': equipment,
    });
  }
}

void main() {
  testWidgets('fonts degrade before any Hive mock', renderFontsFirst);

  /// Opens the sheet, picks today's exercise and returns the labels offered in
  /// its place.
  Future<void> openSubstitutes(WidgetTester tester, String tier,
      Future<void> Function(Set<String> offered) check,
      {bool shared = false, List<String> alsoPlanned = const []}) async {
    late Directory dir;
    late ProviderContainer container;
    await tester.runAsync(() async {
      dir = await setUpHiveForTests();
      container = ProviderContainer();
      await HiveService.instance.exerciseBox.clear();
      await _seed(tier, alsoPlanned: alsoPlanned);
      if (shared) {
        const id = 'shared-id';
        await HiveService.instance.exerciseBox.put(id, <String, dynamic>{
          'id': id,
          'name': 'Shared Move Test',
          'source': 'community',
          'equipment_needed': <String>['bodyweight'],
        });
        await HiveService.instance.customBox
            .put('custom_exercise_9', <String, dynamic>{
          'id': id,
          'type': 'exercise',
          'name': 'Shared Move Test',
          'equipment_needed': <String>[],
        });
      }
    });
    // Tall enough that the lazy list builds every row.
    tester.view.physicalSize = const Size(900, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: Scaffold(body: CoachSwapSheet())),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text(_planned));
    await tester.pumpAndSettle();
    expect(find.text('REPLACE WITH…'), findsOneWidget);

    const names = [
      'Floor Press Test',
      'Dumbbell Press Test',
      'Barbell Row Test',
      'Unlisted Gear Test',
      'No Gear Field Test',
      'Own Move Test',
      'Own Barbell Test',
    ];
    await check({
      for (final n in names)
        if (find.textContaining(n).evaluate().isNotEmpty) n
    });

    await tester.runAsync(() async {
      container.dispose();
      await tearDownHiveForTests(dir);
    });
  }

  const everyName = {
    'Floor Press Test',
    'Dumbbell Press Test',
    'Barbell Row Test',
    'Unlisted Gear Test',
    'No Gear Field Test',
    'Own Move Test',
    'Own Barbell Test',
  };

  double top(WidgetTester tester, String name) =>
      tester.getTopLeft(find.textContaining(name)).dy;

  testWidgets('a full-gym user is offered every exercise', (tester) async {
    await openSubstitutes(tester, 'full_gym', (offered) async {
      expect(offered, everyName);
      expect(find.text('Exercises that match your equipment are listed first.'),
          findsOneWidget);
      expect(top(tester, 'Floor Press Test'),
          lessThan(top(tester, 'Unlisted Gear Test')),
          reason: 'a row with no readable equipment is listed after the matches');
    });
  });

  // A full-gym user is offered hundreds of rows, so the list has a search.
  testWidgets('the search narrows the list by name and older name',
      (tester) async {
    await openSubstitutes(tester, 'full_gym', (offered) async {
      Future<void> type(String text) async {
        await tester.enterText(find.byType(TextField), text);
        await tester.pumpAndSettle();
      }

      int shown(String name) => find.textContaining(name).evaluate().length;
      bool swapEnabled() =>
          tester
              .widget<WardButton>(find.widgetWithText(WardButton, 'SWAP'))
              .onPressed !=
          null;

      await tester.tap(find.textContaining('Floor Press Test'));
      await tester.pumpAndSettle();
      expect(swapEnabled(), isTrue);

      await type('  DUMBBELL   press ');
      expect(shown('Dumbbell Press Test'), 1);
      expect(shown('Floor Press Test'), 0);
      expect(swapEnabled(), isFalse,
          reason: 'a row the search hides must not stay selected');

      await type('old db push');
      expect(shown('Dumbbell Press Test'), 1, reason: 'found by an older name');

      await type('zzz');
      expect(find.text('No exercise matches that search.'), findsOneWidget);

      // A search reaches every exercise, whatever its equipment.
      await type('unlisted gear');
      expect(shown('Unlisted Gear Test'), 1);

      await tester.tap(find.text('BACK'));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
      await tester.tap(find.text(_planned));
      await tester.pumpAndSettle();
      expect(shown('Floor Press Test'), 1, reason: 'BACK clears the search');
    });
  });

  testWidgets('an own custom and its community copy are one row',
      (tester) async {
    await openSubstitutes(tester, 'full_gym', (offered) async {
      expect(find.textContaining('Shared Move Test'), findsOneWidget);
      expect(find.textContaining('Shared Move Test  ·CUSTOM'), findsOneWidget,
          reason: 'the row kept is the author\'s own');
    }, shared: true);
  });

  testWidgets('the search and the list fit a short phone with the keyboard open',
      (tester) async {
    await openSubstitutes(tester, 'full_gym', (offered) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(TextField), findsOneWidget);
      expect(tester.getSize(find.byType(ListView)).height, greaterThan(40));
    });
  });

  testWidgets('a bodyweight user is offered every exercise, their equipment first',
      (tester) async {
    await openSubstitutes(tester, 'bodyweight', (offered) async {
      expect(offered, everyName);
      for (final matching in ['Floor Press Test', 'Own Move Test']) {
        for (final other in ['Barbell Row Test', 'Own Barbell Test']) {
          expect(top(tester, matching), lessThan(top(tester, other)),
              reason: '$matching is listed before $other');
        }
      }
    });
  });

  testWidgets('a name already in the workout is labelled and cannot be picked',
      (tester) async {
    await openSubstitutes(tester, 'bodyweight', (offered) async {
      final taken = find.textContaining('Barbell Row Test  ·'
          '${WardroomCopy.activeAlreadyInWorkoutTag}');
      expect(taken, findsOneWidget);
      await tester.tap(taken);
      await tester.pumpAndSettle();
      expect(
          tester
              .widget<WardButton>(find.widgetWithText(WardButton, 'SWAP'))
              .onPressed,
          isNull);
    }, alsoPlanned: ['Barbell Row Test']);
  });
}
