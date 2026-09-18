// C6/B4 + B1 + B2 (ai-coach-ux-tool-integrity spec 2026-09-18) — widget
// tests for the Compass redesign:
//   1. /PR and /TARGET are REMOVED (they advertised logPR / adjustCaloricTarget,
//      both deleted 2026-05-31 by ADR-0012 — dead-end conversations).
//   2. NO command hands the composer a placeholder token — "[exercise]"-shaped
//      text must never reach the model again (forms compose complete asks).
//   3. Structured commands route to their actions (logWorkout / swap / forms).
//   4. LogWorkoutSheet: prefills from today's plan; confirm submits ONE
//      log_set intent per exercise (trivial class — same plumbing as the
//      model path) and pops.
//   5. CoachSwapSheet: two-step pick (from → to) submits ONE reviewable
//      swap_exercise intent.
//
// HARNESS NOTE (GoogleFonts pitfall, common-pitfalls 2026-08-29): the FIRST
// test below is a typography warmup that runs BEFORE any path_provider mock
// exists — GoogleFonts caches per family+weight there and degrades quietly.
// Hive-using tests install the setUpHiveForTests mock INSIDE the test body
// (never in a global setUp that would precede the warmup), or the mock
// answers GoogleFonts' fetch-and-save path and the network failure surfaces
// as a loud test error.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/core/utils/injury_vocab.dart';
import 'package:icanbefitter/core/utils/ist_date.dart';
import 'package:icanbefitter/shared/widgets/wardroom/ward_button.dart';
import 'package:icanbefitter/features/ai_coach/models/tool_intent.dart';
import 'package:icanbefitter/features/ai_coach/providers/pending_tool_intents_provider.dart';
import 'package:icanbefitter/features/ai_coach/widgets/compass_form_sheet.dart';
import 'package:icanbefitter/features/ai_coach/widgets/compass_tools_sheet.dart';
import 'package:icanbefitter/features/ai_coach/widgets/log_workout_sheet.dart';
import 'package:icanbefitter/features/ai_coach/widgets/swap_exercise_coach_sheet.dart';

import '../helpers/hive_test_setup.dart';

/// Renders every AppTypography style family+weight the widgets in this file
/// use, so GoogleFonts caches them before any path_provider mock is installed.
/// The exact variants matter: WardButton labels (Fraunces SemiBold), the
/// sheet headers (mono w800), and the body/label styles (DM Sans).
class _FontWarmup extends StatelessWidget {
  const _FontWarmup();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text('a', style: AppTypography.body),
        Text('b', style: AppTypography.bodyS),
        Text('c', style: AppTypography.mono),
        Text('d', style: AppTypography.mono.copyWith(
            fontSize: 11, letterSpacing: 2, fontWeight: FontWeight.w800)),
        Text('e', style: AppTypography.body
            .copyWith(fontSize: 13, fontWeight: FontWeight.w700)),
        const WardButton(label: 'CLOSE', onPressed: null),
        const WardButton(label: 'LOG', onPressed: null, variant: WardButtonVariant.outline),
      ],
    );
  }
}

void main() {
  testWidgets('typography warmup — GoogleFonts caches before any Hive mock',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: _FontWarmup())));
    await tester.pump(const Duration(seconds: 1));
    // Quiet-degrade expected — no exception escapes (path_provider mock is
    // NOT installed in this test).
    expect(find.text('a'), findsOneWidget);
  });

  late Directory tempDir;
  late ProviderContainer container;

  Future<void> setUpHive() async {
    tempDir = await setUpHiveForTests();
    container = ProviderContainer();
  }

  Future<void> tearDownHive() async {
    container.dispose();
    await tearDownHiveForTests(tempDir);
  }

  /// Pumps a minimal host that opens the compass sheet like the real input
  /// bar does (modal route, so the sheet's own pop works), and hands every
  /// selection to the [onSelect] spy.
  Future<void> openCompass(
    WidgetTester tester,
    void Function(String prefill, CompassAction action) onSelect,
  ) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (ctx) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () =>
                  CompassToolsSheet.show(ctx, onSelect: onSelect),
              child: const Text('OPEN'),
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OPEN'));
    await tester.pumpAndSettle();
  }

  group('C6/B4 — Compass sheet is a launcher, not a prefill palette', () {
    testWidgets('dead tools /PR and /TARGET are gone', (tester) async {
      var calls = 0;
      await openCompass(tester, (_, _2) => calls++);
      expect(find.text('Log a PR'), findsNothing,
          reason: 'C6/B4 — /PR advertised logPR, removed 2026-05-31 '
              '(ADR-0012 derive-only). Dead-end by construction.');
      expect(find.text('Adjust calorie target'), findsNothing,
          reason: 'C6/B4 — /TARGET advertised adjustCaloricTarget, removed '
              '2026-05-31 (ADR-0012).');
      expect(calls, 0);
    });

    testWidgets('prefill commands hand back placeholder-free text',
        (tester) async {
      // Representative prefill commands from each family (the placeholder
      // class is static data — these rows cover the shape).
      final cases = ['Shorten today', 'Travel workout', 'Pause plan',
        'Meal idea', 'Regenerate plan', 'Progress summary'];
      for (final label in cases) {
        var captured = '';
        await openCompass(tester, (prefill, action) {
          captured = prefill;
          expect(action, CompassAction.prefill,
              reason: '$label should remain a plain prefill');
        });
        await tester.ensureVisible(find.text(label));
        await tester.pumpAndSettle();
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
        expect(captured.isNotEmpty, isTrue, reason: label);
        expect(captured.contains('['), isFalse,
            reason: 'B4 — prefill "$captured" ($label) contains a placeholder '
                'token; placeholder commands must open a form instead.');
      }
    });

    testWidgets('structured commands carry the right action', (tester) async {
      CompassAction? tapped;
      await openCompass(tester, (_, action) => tapped = action);
      await tester.ensureVisible(find.text('Modify for injury'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Modify for injury'));
      await tester.pumpAndSettle();
      expect(tapped, CompassAction.injuryForm,
          reason: 'the placeholder injury command must now route to its form');

      await openCompass(tester, (_, action) => tapped = action);
      await tester.ensureVisible(find.text('Log workout'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Log workout'));
      await tester.pumpAndSettle();
      expect(tapped, CompassAction.logWorkout);

      await openCompass(tester, (_, action) => tapped = action);
      await tester.ensureVisible(find.text('Swap exercise'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Swap exercise'));
      await tester.pumpAndSettle();
      expect(tapped, CompassAction.swap);
    });
  });

  group('B4 — light forms compose complete sentences', () {
    testWidgets('injury form composes the full ask from the chosen token',
        (tester) async {
      String? composed;
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: CompassFormSheet(
        action: CompassAction.injuryForm,
        onCompose: (m) => composed = m,
      ))));
      await tester.pumpAndSettle();

      await tester.tap(find.text(InjuryVocab.chipLabel('knee')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('USE THIS'));
      await tester.pumpAndSettle();

      expect(composed, 'Modify my plan — my knee hurts',
          reason: 'the composed message must be COMPLETE — no placeholder '
              'left for the user to half-edit');
    });
  });

  group('B1 — LogWorkoutSheet structured capture', () {
    testWidgets('prefills from today plan; confirm submits log_set intents',
        (tester) async {
      await tester.runAsync(setUpHive);
      final todayKey = istDateStr(nowWall());
      await tester.runAsync(() => HiveService.instance.workoutBox.put(
        'schedule_$todayKey',
        {
          'type': 'workout',
          'status': 'planned',
          'exercises': <Map<String, dynamic>>[
            {
              'exercise_id': 'ex_bench',
              'exercise_name': 'Bench Press',
              'sets': 4,
              'reps': 8,
              'suggested_weight': 60.0,
            },
            {
              'exercise_id': 'ex_row',
              'exercise_name': 'Barbell Row',
              'sets': 4,
              'reps': 10,
              'suggested_weight': 50.0,
            },
          ],
        },
      ));

      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: LogWorkoutSheet())),
      ));
      await tester.pump(const Duration(milliseconds: 300));

      // Prefilled from the plan prescription.
      expect(find.text('Bench Press'), findsOneWidget);
      expect(find.text('Barbell Row'), findsOneWidget);
      final setsFields = find.widgetWithText(TextField, 'SETS');
      expect(setsFields, findsNWidgets(2));
      expect((tester.widget(setsFields.first) as TextField).controller!.text,
          '4',
          reason: 'sets prefill comes from the plan row, not empty');

      await tester.tap(find.text('LOG WORKOUT'));
      await tester.pumpAndSettle();

      final intents = container.read(pendingToolIntentsProvider);
      expect(intents.length, 2,
          reason: 'one log_set intent per scheduled exercise');
      expect(intents.every((i) => i.type == 'log_set'), isTrue);
      expect(intents.every((i) => i.confirmationClass ==
          ConfirmationClass.trivial), isTrue);
      final bench =
          intents.firstWhere((i) => i.payload['exerciseId'] == 'ex_bench');
      expect(bench.payload['sets'], 4);
      expect(bench.payload['reps'], 8);
      expect(bench.payload['weightKg'], 60.0);
      expect(bench.payload['date'], todayKey);
      await tester.runAsync(tearDownHive);
    });

    testWidgets('empty day shows the empty state and submits nothing',
        (tester) async {
      await tester.runAsync(setUpHive);
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: LogWorkoutSheet())),
      ));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('NO WORKOUT SCHEDULED TODAY'), findsOneWidget,
          reason: '§4.4 rule 13 — plan-less day needs an empty state');
      final intents = container.read(pendingToolIntentsProvider);
      expect(intents, isEmpty);
      await tester.runAsync(tearDownHive);
    });
  });

  group('B2 — CoachSwapSheet structured capture', () {
    testWidgets('two-step pick submits one reviewable swap intent',
        (tester) async {
      await tester.runAsync(setUpHive);
      final todayKey = istDateStr(nowWall());
      await tester.runAsync(() => HiveService.instance.workoutBox.put(
        'schedule_$todayKey',
        {
          'type': 'workout',
          'status': 'planned',
          'exercises': <Map<String, dynamic>>[
            {
              'exercise_id': 'ex_bench',
              'exercise_name': 'Bench Press',
              'sets': 4,
              'reps': 8,
            },
          ],
        },
      ));
      // Seed the library so the substitute picker has capability-safe options
      // (empty box → empty list → the test would tap the BACK tile).
      await tester.runAsync(() {
        HiveService.instance.exerciseBox.put('ex_pushup', {
          'id': 'ex_pushup',
          'name': 'Push Up',
          'equipment_needed': 'bodyweight',
        });
        return HiveService.instance.exerciseBox.put('ex_dbpress', {
          'id': 'ex_dbpress',
          'name': 'Dumbbell Press',
          'equipment_needed': 'home_dumbbells',
        });
      });

      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: CoachSwapSheet())),
      ));
      await tester.pumpAndSettle();

      // Step 1: pick the exercise to replace.
      expect(find.text('SWAP WHICH EXERCISE?'), findsOneWidget);
      await tester.tap(find.text('Bench Press'));
      await tester.pumpAndSettle();

      // Step 2: pick a substitute — the seeded library must offer at least
      // one capability-safe option; pick the first row.
      expect(find.text('REPLACE WITH…'), findsOneWidget);
      final options = find.byType(InkWell);
      expect(options, findsWidgets,
          reason: 'substitute list must not be empty in the test library');
      await tester.tap(options.first, warnIfMissed: false);
      await tester.pumpAndSettle();

      await tester.tap(find.text('SWAP'));
      await tester.pumpAndSettle();

      final intents = container.read(pendingToolIntentsProvider);
      expect(intents.length, 1);
      expect(intents.first.type, 'swap_exercise');
      expect(intents.first.payload['exerciseId'], 'ex_bench');
      expect(intents.first.payload['newExerciseId'], isNotEmpty);
      expect(intents.first.confirmationClass, ConfirmationClass.reviewable,
          reason: 'the swap must flow through the existing reviewable '
              'preview card, exactly like the model path');
      await tester.runAsync(tearDownHive);
    });

    // FINDING 5 (MED): _loadToday read the raw schedule row with no status
    // guard — a dead-end picker on moved/completed days (a moved row's
    // exercises don't belong to today anymore; a completed day is done).
    // Fix: the SAME raw+guard pattern log_workout_sheet.dart uses, with an
    // HONEST message per state.
    testWidgets('terminal moved day shows the honest empty state, no intents',
        (tester) async {
      await tester.runAsync(setUpHive);
      final todayKey = istDateStr(nowWall());
      await tester.runAsync(() => HiveService.instance.workoutBox.put(
        'schedule_$todayKey',
        {
          'type': 'workout',
          'status': 'moved',
          'moved_to': istDateStr(nowWall().add(const Duration(days: 1))),
          'exercises': <Map<String, dynamic>>[
            {'exercise_id': 'ex_bench', 'exercise_name': 'Bench Press'},
          ],
        },
      ));

      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: CoachSwapSheet())),
      ));
      await tester.pumpAndSettle();

      expect(find.text('SWAP WHICH EXERCISE?'), findsNothing,
          reason: 'a moved day has nothing to swap — the picker must not '
              'render the moved-away exercises');
      expect(find.textContaining('No swappable workout scheduled today'),
          findsOneWidget);
      expect(container.read(pendingToolIntentsProvider), isEmpty);
      await tester.runAsync(tearDownHive);
    });

    testWidgets('completed day points at the Train screen instead',
        (tester) async {
      await tester.runAsync(setUpHive);
      final todayKey = istDateStr(nowWall());
      await tester.runAsync(() => HiveService.instance.workoutBox.put(
        'schedule_$todayKey',
        {
          'type': 'workout',
          'status': 'completed',
          'exercises': <Map<String, dynamic>>[
            {'exercise_id': 'ex_bench', 'exercise_name': 'Bench Press'},
          ],
        },
      ));

      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: CoachSwapSheet())),
      ));
      await tester.pumpAndSettle();

      expect(find.textContaining('already done'), findsOneWidget,
          reason: 'the completed-day message must say WHERE to edit instead '
              'of the generic no-workout text');
      expect(find.textContaining('Train screen'), findsOneWidget);
      expect(container.read(pendingToolIntentsProvider), isEmpty);
      await tester.runAsync(tearDownHive);
    });

    // FINDING B2 (LOW-MED, review round 2): the round-1 guard refused ANY
    // status != 'planned', but the dispatcher explicitly keeps PAUSED days
    // swappable (paused = pending, not terminal — tool_dispatcher.dart
    // _executeSwapExercise guards TERMINAL rows + completed only). Fix:
    // `paused` passes the guard and renders the picker; the submitted swap
    // executes normally through the dispatcher's own guards.
    testWidgets('paused day renders the picker and submits normally',
        (tester) async {
      await tester.runAsync(setUpHive);
      final todayKey = istDateStr(nowWall());
      await tester.runAsync(() => HiveService.instance.workoutBox.put(
        'schedule_$todayKey',
        {
          'type': 'workout',
          'status': 'paused',
          'exercises': <Map<String, dynamic>>[
            {
              'exercise_id': 'ex_bench',
              'exercise_name': 'Bench Press',
              'sets': 4,
              'reps': 8,
            },
          ],
        },
      ));
      await tester.runAsync(() => HiveService.instance.exerciseBox.put(
        'ex_pushup',
        {
          'id': 'ex_pushup',
          'name': 'Push Up',
          'equipment_needed': 'bodyweight',
        },
      ));

      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: CoachSwapSheet())),
      ));
      await tester.pumpAndSettle();

      // Pre-fix the guard blocked paused → dead-end empty state.
      expect(find.text('SWAP WHICH EXERCISE?'), findsOneWidget,
          reason: 'a paused day is PENDING, not terminal — the picker must '
              'render exactly as it does for a planned day');
      expect(find.text('Bench Press'), findsOneWidget);
      expect(container.read(pendingToolIntentsProvider), isEmpty);

      // Full flow still submits one reviewable intent.
      await tester.tap(find.text('Bench Press'));
      await tester.pumpAndSettle();
      final options = find.byType(InkWell);
      expect(options, findsWidgets);
      await tester.tap(options.first, warnIfMissed: false);
      await tester.pumpAndSettle();
      await tester.tap(find.text('SWAP'));
      await tester.pumpAndSettle();

      final intents = container.read(pendingToolIntentsProvider);
      expect(intents.length, 1);
      expect(intents.first.type, 'swap_exercise');
      expect(intents.first.payload['exerciseId'], 'ex_bench');
      await tester.runAsync(tearDownHive);
    });

    testWidgets('paused day renders the LOG sheet picker too (R2-B2 '
        'consistency — log sheet honors the same paused=pending contract)',
        (tester) async {
      await tester.runAsync(setUpHive);
      final todayKey = istDateStr(nowWall());
      await tester.runAsync(() => HiveService.instance.workoutBox.put(
        'schedule_$todayKey',
        {
          'type': 'workout',
          'status': 'paused',
          'exercises': <Map<String, dynamic>>[
            {
              'exercise_id': 'ex_bench',
              'exercise_name': 'Bench Press',
              'sets': 4,
              'reps': 8,
              'suggested_weight': 60.0,
            },
          ],
        },
      ));

      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: LogWorkoutSheet())),
      ));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Bench Press'), findsOneWidget,
          reason: 'paused = pending: the log sheet must render the paused '
              'day exactly like a planned day (same contract the dispatcher '
              'and swap sheet honor)');
      expect(container.read(pendingToolIntentsProvider), isEmpty);
      await tester.runAsync(tearDownHive);
    });
  });

  group('B4 review — scheduleForm TOMORROW labels the actual date', () {
    // FINDING 8 (LOW): the destination chip whose WEEKDAY matched the SOURCE
    // choice was labeled 'TOMORROW'. Fix: the chip whose DATE == today+1.
    // Discriminating assertion: pick the source = weekday(today+2) (never
    // tomorrow's weekday — the 7 chips cover 7 distinct weekdays), then the
    // destination Wrap's labels must show 'TOMORROW' at index 1 (today+1),
    // NOT at the source's index (today+2 — the pre-fix position).
    testWidgets('TOMORROW sits on the chip for today+1, not the source day',
        (tester) async {
      String? composed;
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: CompassFormSheet(
        action: CompassAction.scheduleForm,
        onCompose: (m) => composed = m,
      ))));
      await tester.pumpAndSettle();

      final today = nowWall();
      final sourceWeekday = const [
        'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday',
        'Sunday',
      ][today.add(const Duration(days: 2)).weekday - 1];

      await tester.tap(find.text(sourceWeekday).first);
      await tester.pumpAndSettle();

      // Destination row = the LAST Wrap's Texts, in chip order i=0..6.
      final wraps = find.byType(Wrap);
      expect(wraps, findsNWidgets(2));
      final destLabels = tester
          .widgetList<Text>(
              find.descendant(of: wraps.last, matching: find.byType(Text)))
          .map((t) => t.data)
          .toList();
      expect(destLabels.length, 7);
      expect(destLabels[1], 'TOMORROW',
          reason: 'the chip for today+1 must be labeled TOMORROW (pre-fix '
              'the label sat on whichever chip matched the SOURCE weekday — '
              'here index 2)');
      expect(destLabels[2], sourceWeekday,
          reason: 'the source day\'s own date chip must keep its weekday '
              'label');
      expect(destLabels.where((l) => l == 'TOMORROW').length, 1);
      expect(composed, isNull, reason: 'form not submitted yet');
    });
  });

  group('B1 review — parse-validity gates the confirm button', () {
    // FINDING 9 (LOW): isComplete only checked non-empty; 'abc' coerced to
    // 0.0 / 0 / 1 at dispatch. Fix: each field must PARSE (weight double,
    // reps/sets int) before confirm enables.
    testWidgets('garbage in the KG field disables LOG WORKOUT',
        (tester) async {
      await tester.runAsync(setUpHive);
      final todayKey = istDateStr(nowWall());
      await tester.runAsync(() => HiveService.instance.workoutBox.put(
        'schedule_$todayKey',
        {
          'type': 'workout',
          'status': 'planned',
          'exercises': <Map<String, dynamic>>[
            {
              'exercise_id': 'ex_bench',
              'exercise_name': 'Bench Press',
              'sets': 4,
              'reps': 8,
              'suggested_weight': 60.0,
            },
          ],
        },
      ));

      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: LogWorkoutSheet())),
      ));
      await tester.pump(const Duration(milliseconds: 300));

      // Sanity: valid prefill → enabled.
      var btn = tester.widget<WardButton>(
          find.widgetWithText(WardButton, 'LOG WORKOUT'));
      expect(btn.onPressed, isNotNull,
          reason: 'prefilled values parse — confirm must be enabled');

      await tester.enterText(
          find.widgetWithText(TextField, 'KG').first, 'abc');
      await tester.pump();

      btn = tester.widget<WardButton>(
          find.widgetWithText(WardButton, 'LOG WORKOUT'));
      expect(btn.onPressed, isNull,
          reason: '\'abc\' does not parse as a double — confirm must DISABLE '
              'instead of coercing to 0.0 at dispatch');
      expect(container.read(pendingToolIntentsProvider), isEmpty);
      await tester.runAsync(tearDownHive);
    });
  });
}
