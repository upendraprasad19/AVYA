// OI-361, the chat path (docs/plans/log-exercise-flip.md §3b, R7-02): a chat
// workout draft with no set to write never completes the day. One predicate,
// `draftHasLoggableSet`, is shared by `submitWorkoutDraft` (returns before any
// write) and `WorkoutLogConfirmCard` (CONFIRM disabled, reason shown). The
// Active Workout half of OI-361 is U-E1 in log_exercise_flip_behavioral_test.
//
// ORDER IS LOAD-BEARING (card_harness.dart, exercise_plate_widgets_test.dart):
// the first widget test renders every font family with NO path_provider mock;
// Hive opens lazily inside `runAsync` afterwards and closes in tearDownAll.
@Timeout(Duration(minutes: 3))
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/copy/wardroom_copy.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/features/ai_coach/providers/ai_coach_provider.dart';
import 'package:icanbefitter/features/ai_coach/services/conversational_log_handler.dart';
import 'package:icanbefitter/features/ai_coach/widgets/workout_log_confirm_card.dart';
import 'package:icanbefitter/features/auth/providers/auth_invalidation_provider.dart';

import '../helpers/hive_test_setup.dart';

class _SeededDraft extends WorkoutDraftNotifier {
  _SeededDraft(this.seed);
  final WorkoutDraft seed;
  @override
  WorkoutDraft? build() => seed;
}

WorkoutDraft draft(List<DraftExercise> exercises) =>
    WorkoutDraft(id: 'wdraft_test', exercises: exercises, date: DateTime.now());

DraftExercise lift(String name, {int sets = 0}) => DraftExercise(
    name: name,
    loggingType: 'weight_reps',
    sets: [for (var i = 0; i < sets; i++) DraftSet(weightKg: 40, reps: 8)]);

bool anyKey(String prefix) => HiveService.instance.workoutBox.keys
    .any((k) => k.toString().startsWith(prefix));

void main() {
  group('U-E4: draftHasLoggableSet (pure)', () {
    test('no exercise with sets: false', () {
      expect(draftHasLoggableSet(draft([lift('Squat'), lift('Row')])), isFalse);
    });
    test('one exercise with a set: true', () {
      expect(draftHasLoggableSet(draft([lift('Squat'), lift('Row', sets: 1)])),
          isTrue);
    });
    test('all-blank sets are not loggable and are never written (B-pass 1)',
        () {
      final blank = DraftExercise(
          name: 'Squat', loggingType: 'weight_reps', sets: [DraftSet()]);
      expect(draftHasLoggableSet(draft([blank])), isFalse);
      final mixed = DraftExercise(
          name: 'Row',
          loggingType: 'weight_reps',
          sets: [DraftSet(), DraftSet(weightKg: 40, reps: 8)]);
      expect(draftExerciseSets(mixed).length, 1);
      expect(
          draftHasLoggableSet(draft([
            DraftExercise(name: 'Run', loggingType: 'cardio', sets: []),
          ])),
          isFalse,
          reason: 'cardio with no duration and no distance');
      expect(
          draftHasLoggableSet(draft([
            DraftExercise(
                name: 'Run', loggingType: 'cardio', sets: [], distanceKm: 5),
          ])),
          isTrue);
    });

    test('cardio counts (its synthetic set)', () {
      expect(
          draftHasLoggableSet(draft([
            DraftExercise(
                name: 'Run', loggingType: 'cardio', sets: [], durationMins: 20),
          ])),
          isTrue);
    });
  });

  group('U-E5: no-set drafts never complete (behavioural)', () {
    Directory? dir;
    Future<void> ensureHive(WidgetTester tester) async {
      dir ??= await tester.runAsync(setUpHiveForTests);
    }

    tearDownAll(() async {
      if (dir != null) await tearDownHiveForTests(dir!);
    });

    Future<void> renderFontsFirst(WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Column(children: [
          Text('a', style: AppTypography.h2),
          Text('b', style: AppTypography.h3),
          Text('c', style: AppTypography.mono),
          Text('d', style: AppTypography.monoXs),
          Text('e', style: AppTypography.bodySm),
          Text('f', style: AppTypography.body),
        ]),
      ));
    }

    testWidgets('fonts degrade before any Hive mock', renderFontsFirst);

    Future<ProviderContainer> pumpWithDraft(
        WidgetTester tester, WorkoutDraft seed, void Function(WidgetRef) onRef) async {
      final c = ProviderContainer(overrides: [
        authUserIdTokenProvider.overrideWithValue('u'),
        workoutDraftProvider.overrideWith(() => _SeededDraft(seed)),
      ]);
      addTearDown(c.dispose);
      await tester.pumpWidget(UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: Consumer(builder: (context, ref, _) {
                onRef(ref);
                return const WorkoutLogConfirmCard();
              }),
            ),
          ),
        ),
      ));
      return c;
    }

    testWidgets('submitWorkoutDraft writes nothing and keeps the draft; the '
        'card disables CONFIRM and says why', (tester) async {
      await ensureHive(tester);
      late WidgetRef ref;
      final seed = draft([lift('Squat'), lift('Row')]);
      final c = await pumpWithDraft(tester, seed, (r) => ref = r);

      // The card states the block.
      expect(find.text(WardroomCopy.coachDraftNoSets), findsOneWidget);

      // CONFIRM is disabled on the card itself, not only by the submit's guard.
      final confirm = tester.widget<GestureDetector>(find
          .ancestor(
              of: find.text('CONFIRM \u00B7 LOG WORKOUT'),
              matching: find.byType(GestureDetector))
          .first);
      expect(confirm.onTap, isNull);

      // Tapping CONFIRM does nothing (onTap is null).
      await tester.runAsync(() async {
        await tester.tap(find.text('CONFIRM · LOG WORKOUT'));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump();
      expect(anyKey('wlog_'), isFalse);
      expect(c.read(workoutDraftProvider), isNotNull);

      // The submit's own guard, for any other caller.
      await tester.runAsync(() => submitWorkoutDraft(seed, ref));
      expect(anyKey('wlog_'), isFalse,
          reason: 'a no-set draft must not synthesize a completed day');
      expect(anyKey('exlog_'), isFalse);
      expect(c.read(workoutDraftProvider), isNotNull,
          reason: 'the draft stays so the user can add sets or discard');

      await tester.runAsync(() => tester.pumpWidget(const SizedBox()));
    });

    testWidgets('a draft with a set still logs and completes', (tester) async {
      await ensureHive(tester);
      late WidgetRef ref;
      final seed = draft([lift('Squat', sets: 2), lift('Row')]);
      await pumpWithDraft(tester, seed, (r) => ref = r);
      expect(find.text(WardroomCopy.coachDraftNoSets), findsNothing);

      await tester.runAsync(() => submitWorkoutDraft(seed, ref));
      expect(anyKey('exlog_'), isTrue);
      expect(anyKey('wlog_'), isTrue);

      await tester.runAsync(() => tester.pumpWidget(const SizedBox()));
    });
  });
}
