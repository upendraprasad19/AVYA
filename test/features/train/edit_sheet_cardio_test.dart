// OI-389 Batch 1a, the edit sheet as the user sees it (plan §4 T8 rendered
// legs, T20, T30): the cardio MIN box takes decimals (D2) and shows no seconds
// hint; a refused row keeps the sheet open with failure copy, never
// "Workout log updated"; a partial failure names only the failed exercise and
// still invalidates the providers so the saved rows show. The update map's
// pure legs live in test/contracts/cardio_duration_distance_writer_to_reader_test.dart.
@Timeout(Duration(minutes: 4))
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/copy/set_log_copy.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/workout_write_service.dart';
import 'package:icanbefitter/core/services/write_result.dart';
import 'package:icanbefitter/features/auth/providers/auth_invalidation_provider.dart';
import 'package:icanbefitter/features/home/providers/home_provider.dart';
import 'package:icanbefitter/features/train/repositories/workout_repository.dart';
import 'package:icanbefitter/features/train/widgets/edit_workout_log_sheet.dart';

import '../../helpers/hive_test_setup.dart';
import 'log_exercise/card_harness.dart';

int _prBuilds = 0;

class _CountingPRs extends AllExercisePRsNotifier {
  @override
  List<ExercisePR> build() {
    _prBuilds++;
    return const [];
  }
}

final _day = DateTime(2026, 10, 20, 9);

Future<void> _seed(WidgetTester tester, List<(String, String, ExerciseSet)> rows) =>
    tester.runAsync(() async {
      await HiveService.instance.workoutBox.clear();
      final exb = HiveService.instance.exerciseBox;
      for (final (name, type, set) in rows) {
        await exb.put('lib_$name', {'name': name, 'logging_type': type});
        final r = await WorkoutWriteService.instance.logExercise(
            date: _day,
            exerciseName: name,
            sets: [set],
            source: WriteSource.activeWorkout);
        expect(r.success, isTrue, reason: r.errorMessage);
      }
    });

Future<ProviderContainer> _pumpSheet(WidgetTester tester) async {
  _prBuilds = 0;
  final c = ProviderContainer(overrides: [
    authUserIdTokenProvider.overrideWithValue(kTestUserId),
    allExercisePRsProvider.overrideWith(_CountingPRs.new),
  ]);
  addTearDown(c.dispose);
  c.listen(allExercisePRsProvider, (_, _) {});
  // Pushed as a route (not the app's home) so a pop on failure would really
  // remove it: M46 must be observable.
  final nav = GlobalKey<NavigatorState>();
  await tester.pumpWidget(UncontrolledProviderScope(
    container: c,
    child: MaterialApp(navigatorKey: nav, home: const Scaffold()),
  ));
  nav.currentState!.push(MaterialPageRoute<void>(
      builder: (_) => Scaffold(
            body: SingleChildScrollView(child: EditWorkoutLogSheet(date: _day)),
          )));
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
  return c;
}

Finder _fieldWith(String text) => find.byWidgetPredicate(
    (w) => w is TextField && w.controller?.text == text);

Map _stored(String name) => HiveService.instance.workoutBox
    .get(WorkoutWriteService.exlogKey(_day, name)) as Map;

const _rowing = ExerciseSet(weightKg: 0, reps: 0, durationSec: 750, distanceKm: 5);

void main() {
  tearDownAll(closeHive);
  testWidgets('fonts degrade before any Hive mock', renderFontsFirst);

  testWidgets('T8: "13.5" typed into the rendered MIN box saves 810 s, and '
      'the box shows no seconds hint', (tester) async {
    await ensureHive(tester);
    await _seed(tester, [('Rowing Machine', 'cardio', _rowing)]);
    await _pumpSheet(tester);
    expect(_fieldWith('12.5'), findsOneWidget, reason: '750 s prefills 12.5');
    await tester.enterText(_fieldWith('12.5'), '90');
    await tester.pump();
    expect(find.textContaining('1m 30s'), findsNothing,
        reason: 'a minutes box shows no seconds hint');
    await tester.enterText(_fieldWith('90'), '13.5');
    await tester.pump();
    expect(_fieldWith('13.5'), findsOneWidget,
        reason: 'the field admits a decimal point');
    await tapWithRealIo(tester, find.text('SAVE CHANGES'));
    final set = (_stored('Rowing Machine')['sets'] as List).single as Map;
    expect(set['duration_sec'], 810);
    expect(set['distance_km'], 5.0);
  });

  testWidgets('T20: a refused row keeps the sheet open with failure copy',
      (tester) async {
    await ensureHive(tester);
    await _seed(tester, [('Rowing Machine', 'cardio', _rowing)]);
    await _pumpSheet(tester);
    await tester.enterText(_fieldWith('12.5'), '12.5.');
    await tapWithRealIo(tester, find.text('SAVE CHANGES'));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Workout log updated'), findsNothing);
    expect(find.text(kNotSavedMinutesFormat), findsOneWidget);
    expect(find.byType(EditWorkoutLogSheet), findsOneWidget);
    final set = (_stored('Rowing Machine')['sets'] as List).single as Map;
    expect(set['duration_sec'], 750, reason: 'never saved as 0');
  });

  testWidgets('T30: partial failure names only the failed row, stays open, '
      'and still invalidates the providers', (tester) async {
    await ensureHive(tester);
    await _seed(tester, [
      ('Rowing Machine', 'cardio', _rowing),
      ('Bench Press', 'weight_reps',
          const ExerciseSet(weightKg: 60, reps: 8)),
      ('Plank', 'timed', const ExerciseSet(weightKg: 0, reps: 0, durationSec: 45)),
    ]);
    await _pumpSheet(tester);
    final before = _prBuilds;
    await tester.enterText(_fieldWith('12.5'), '12.5.');
    await tester.enterText(_fieldWith('8'), '9');
    await tapWithRealIo(tester, find.text('SAVE CHANGES'));
    await tester.pump(const Duration(seconds: 1));
    expect(
        find.text(partialSaveCopy(['Rowing Machine'],
            firstCode: kMinutesFormatCode)),
        findsOneWidget);
    expect(find.byType(EditWorkoutLogSheet), findsOneWidget);
    expect(_prBuilds, greaterThan(before),
        reason: 'the saved rows show at once');
    expect(_stored('Bench Press')['reps_completed'], 9);
  });

  testWidgets('T8 hint leg: a restored cardio row\'s MIN box shows no seconds '
      'hint', (tester) async {
    await ensureHive(tester);
    await tester.runAsync(() async {
      await HiveService.instance.workoutBox.clear();
      await HiveService.instance.workoutBox
          .put(WorkoutWriteService.exlogKey(_day, 'Rowing Machine'), {
        'exercise_name': 'Rowing Machine',
        'date': '2026-10-20',
        'logging_type': 'cardio',
        'set_number': 1,
        'duration_seconds': 600,
        'distance_km': 5.0,
      });
      await HiveService.instance.workoutBox.put('exercise_log_index_2026-10-20',
          [WorkoutWriteService.exlogKey(_day, 'Rowing Machine')]);
    });
    await _pumpSheet(tester);
    expect(find.text('DURATION (MIN)'), findsOneWidget);
    expect(_fieldWith('10'), findsOneWidget, reason: '600 s prefills 10 min');
    await tester.enterText(_fieldWith('10'), '90');
    await tester.pump();
    expect(find.textContaining('1m 30s'), findsNothing);
  });
}
