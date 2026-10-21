// OI-370 / B' (diagnose: docs/diagnoses/2026-10-21-coach-workout-card-false-success-*.md;
// plan docs/plans/train-coach-log-refresh.md §3 "B' widget, through the real slot").
//
// The chat workout card, rendered through the real `WorkoutDraftSlot` over a
// real Hive temp dir: the saved state, honest failure (partial / none saved /
// day not marked / skipped), the held card, the id guards, the edit sheet and
// its input filter, the TalkBack labels and large text.
//
// ORDER IS LOAD-BEARING (zero_set_completion_behavioral_test.dart): the first
// widget test renders every font family with NO path_provider mock; Hive opens
// lazily inside `runAsync` afterwards and closes in tearDownAll.
@Timeout(Duration(minutes: 5))
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart'
    show Override, ProviderBase;
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:icanbefitter/core/copy/wardroom_copy.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/core/utils/ist_date.dart';
import 'package:icanbefitter/features/ai_coach/copy/workout_draft_copy.dart';
import 'package:icanbefitter/features/ai_coach/providers/ai_coach_provider.dart';
import 'package:icanbefitter/features/ai_coach/services/conversational_log_handler.dart';
import 'package:icanbefitter/features/ai_coach/widgets/workout_draft_slot.dart';
import 'package:icanbefitter/features/ai_coach/widgets/workout_log_confirm_card.dart';
import 'package:icanbefitter/features/auth/providers/auth_invalidation_provider.dart';
import 'package:icanbefitter/features/train/providers/train_provider.dart';

import '../helpers/hive_test_setup.dart';
import '../helpers/workout_draft_seed.dart';

const kConfirm = 'CONFIRM · LOG WORKOUT';
const kShortHold = Duration(milliseconds: 150);
const kLongHold = Duration(milliseconds: 500);

Directory? dir;

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
    ]),
  ));
}

Future<void> ensureHive(WidgetTester tester) async {
  dir ??= await tester.runAsync(setUpHiveForTests);
  await tester.runAsync(() => HiveService.instance.workoutBox.clear());
}

// ── Draft builders ──────────────────────────────────────────────────

DraftExercise lift(String name, double kg, int reps, {int sets = 3}) =>
    DraftExercise(
      name: name,
      loggingType: 'weight_reps',
      sets: [for (var i = 0; i < sets; i++) DraftSet(weightKg: kg, reps: reps)],
    );

DraftExercise bad(String name) => DraftExercise(
    name: name,
    loggingType: 'weight_reps',
    sets: [DraftSet(weightKg: -5, reps: 8)]);

DraftExercise emptyPlank() =>
    DraftExercise(name: 'Plank', loggingType: 'timed', sets: []);

DraftExercise badPlank() => DraftExercise(
    name: 'Plank',
    loggingType: 'timed',
    sets: [DraftSet(reps: 8, durationSecs: -100)]);

WorkoutDraft draftOf(List<DraftExercise> ex, {String id = 'wdraft_a'}) =>
    WorkoutDraft(id: id, exercises: ex, date: DateTime.now());

Map<String, dynamic> coachData(String name) => {
      'exercises': [
        {
          'name': name,
          'logging_type': 'weight_reps',
          'sets': [
            {'weight_kg': 80, 'reps': 5},
          ],
        },
      ],
    };

// ── Hive reads ──────────────────────────────────────────────────────

Box get box => HiveService.instance.workoutBox;

List<Map> rows(String prefix) => [
      for (final k in box.keys)
        if (k.toString().startsWith(prefix)) box.get(k) as Map,
    ];

Map? exlogFor(String name) {
  for (final r in rows('exlog_')) {
    if (r['exercise_name'] == name) return r;
  }
  return null;
}

// ── Harness ─────────────────────────────────────────────────────────

/// Records every provider the container disposes: an `invalidate` of a
/// provider that was read disposes it (probed on riverpod 3.2.1).
final class DisposeLog extends ProviderObserver {
  final disposed = <ProviderBase<Object?>>[];
  @override
  void didDisposeProvider(ProviderObserverContext context) =>
      disposed.add(context.provider);
}

List<Override> slotOverrides(String token, WorkoutDraft? seed) => [
      authUserIdTokenProvider.overrideWithValue(token),
      if (seed != null)
        workoutDraftProvider
            .overrideWith(() => SeededWorkoutDraftNotifier(seed)),
    ];

class Slot {
  final ProviderContainer c;
  final WorkoutDraft? seed;
  late WidgetRef ref;
  Slot(this.c, this.seed);
  WorkoutDraft? get draft => c.read(workoutDraftProvider);
  WorkoutDraftNotifier get n => c.read(workoutDraftProvider.notifier);

  /// An auth change: the draft notifier rebuilds (lazily, on the next read).
  /// The override list keeps its length (riverpod `updateOverrides`).
  void flipAuth(String token) {
    c.updateOverrides(slotOverrides(token, seed));
    c.read(workoutDraftProvider);
  }
}

Future<Slot> pumpSlot(
  WidgetTester tester, {
  WorkoutDraft? seed,
  double scale = 1.0,
  double width = 420,
  int fillers = 0,
  List<ProviderObserver> observers = const [],
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = Size(width, 1600);
  addTearDown(tester.view.reset);
  final c = ProviderContainer(
      overrides: slotOverrides('u', seed), observers: observers);
  addTearDown(c.dispose);
  final s = Slot(c, seed);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: c,
    child: MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Scaffold(
        body: Column(children: [
          Consumer(builder: (context, ref, _) {
            s.ref = ref;
            return const SizedBox.shrink();
          }),
          Expanded(
            child: ListView.builder(
              itemCount: 1 + fillers,
              itemBuilder: (context, i) => i == 0
                  ? const WorkoutDraftSlot()
                  : const SizedBox(height: 600),
            ),
          ),
        ]),
      ),
    ),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 250));
  return s;
}

/// Waits (real time) until no submit is running.
Future<void> untilIdle(Slot s) async {
  for (var i = 0; i < 300 && (s.draft?.isSubmitting ?? false); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

/// Taps [f] (a write) and waits for the submit to end.
Future<void> tapWrite(WidgetTester tester, Slot s, Finder f) async {
  await tester.runAsync(() async {
    await tester.tap(f);
    await untilIdle(s);
  });
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 250));
}

Future<void> confirm(WidgetTester tester, Slot s) =>
    tapWrite(tester, s, find.text(kConfirm));

/// Lets the real hold timer run for [d].
Future<void> waitReal(WidgetTester tester, Duration d) async {
  await tester.runAsync(() => Future<void>.delayed(d));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 250));
}

Future<void> openGate(WidgetTester tester, Completer<void> gate, Slot s) async {
  await tester.runAsync(() async {
    gate.complete();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await untilIdle(s);
  });
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 250));
}

Future<void> closeSheet(WidgetTester tester, String title) async {
  Navigator.of(tester.element(find.text(title))).pop();
  await tester.pumpAndSettle();
}

Future<void> openSheetFor(WidgetTester tester, int row) async {
  await tester.tap(find.byIcon(Icons.edit_outlined).at(row));
  await tester.pumpAndSettle();
}

/// The one live-region node under the card.
SemanticsNode liveNode(WidgetTester tester) {
  final f = find.descendant(
    of: find.byType(WorkoutLogConfirmCard),
    matching: find.byWidgetPredicate(
        (w) => w is Semantics && (w.properties.liveRegion ?? false)),
  );
  return tester.getSemantics(f.first);
}

Finder semanticsLabel(String label) => find.bySemanticsLabel(label);

/// Unmounts the tree and lets any pending fake timers run.
Future<void> done(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  testWidgets('fonts degrade before any Hive mock', renderFontsFirst);

  setUp(() {
    WorkoutDraftNotifier.savedHoldFor =
        (hasNote) => hasNote ? kLongHold : kShortHold;
    DraftSubmitDebug.debugSubmitGate = null;
    DraftSubmitDebug.debugBeforeMarkGate = null;
    DraftSubmitDebug.clock = DateTime.now;
  });

  tearDown(() {
    WorkoutDraftNotifier.savedHoldFor =
        WorkoutDraftNotifier.defaultSavedHoldFor;
    DraftSubmitDebug.debugSubmitGate = null;
    DraftSubmitDebug.debugBeforeMarkGate = null;
    DraftSubmitDebug.clock = DateTime.now;
  });

  tearDownAll(() async {
    if (dir != null) await tearDownHiveForTests(dir!);
  });

  group('saved', () {
    testWidgets('header, WORKOUT LOGGED + tick, live region, pencils hidden; '
        'the slot is empty after the hold', (tester) async {
      await ensureHive(tester);
      final sem = tester.ensureSemantics();
      final s = await pumpSlot(tester,
          seed: draftOf([lift('Bench Press', 60, 8)]));
      expect(semanticsLabel('Edit Bench Press'), findsOneWidget);
      await confirm(tester, s);

      expect(s.draft!.status, DraftCardStatus.saved);
      expect(find.text(WardroomCopy.coachWorkoutLoggedHeader), findsOneWidget);
      expect(find.text(WardroomCopy.coachWorkoutLogged), findsOneWidget);
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
      expect(liveNode(tester),
          isSemantics(isLiveRegion: true, label: 'WORKOUT LOGGED'));
      expect(semanticsLabel('Edit Bench Press'), findsNothing);
      expect(find.text(kConfirm), findsNothing);
      expect(rows('exlog_'), hasLength(1));
      expect(rows('wlog_'), hasLength(1));

      // A saved card takes no edit.
      final before = s.draft;
      s.n.updateSet(before!.id, 0, 0, DraftSet(weightKg: 99, reps: 1));
      expect(identical(s.draft, before), isTrue);

      await waitReal(tester, kShortHold + const Duration(milliseconds: 100));
      expect(s.draft, isNull);
      expect(find.byType(WorkoutLogConfirmCard), findsNothing);
      sem.dispose();
      await done(tester);
    });
  });

  group('haptic', () {
    testWidgets('one light impact when a card turns saved; none on a partial',
        (tester) async {
      // B-pass fb5048e68fae F11.
      await ensureHive(tester);
      final calls = <Object?>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform, (call) async {
        if (call.method == 'HapticFeedback.vibrate') calls.add(call.arguments);
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null));
      final s = await pumpSlot(tester,
          seed: draftOf([lift('Bench Press', 60, 8), bad('X')]));
      await confirm(tester, s);
      expect(s.draft!.status, DraftCardStatus.partial);
      expect(calls, isEmpty);
      s.n.updateSet(s.draft!.id, 0, 0, DraftSet(weightKg: 5, reps: 8));
      await tester.pump();
      await confirm(tester, s);
      expect(s.draft!.status, DraftCardStatus.saved);
      expect(calls, ['HapticFeedbackType.lightImpact']);
      await waitReal(tester, kShortHold + const Duration(milliseconds: 100));
      await done(tester);
    });
  });

  group('submitting', () {
    testWidgets('spinner, Saving workout disabled, DISCARD disabled, pencils '
        'hidden with their slots kept; a second submit is refused',
        (tester) async {
      await ensureHive(tester);
      final sem = tester.ensureSemantics();
      final d = draftOf([lift('Bench Press', 60, 8)]);
      final s = await pumpSlot(tester, seed: d);
      final gate = DraftSubmitDebug.debugSubmitGate = Completer<void>();
      await tester.runAsync(() => tester.tap(find.text(kConfirm)));
      await tester.pump();

      expect(s.draft!.isSubmitting, isTrue);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(
          tester.getSemantics(semanticsLabel(
              WardroomCopy.coachWorkoutSavingSemantics)),
          isSemantics(
              isButton: true, hasEnabledState: true, isEnabled: false));
      expect(
          tester.getSemantics(
              semanticsLabel(WardroomCopy.coachWorkoutDiscardSemantics)),
          isSemantics(
              isButton: true, hasEnabledState: true, isEnabled: false));
      expect(semanticsLabel('Edit Bench Press'), findsNothing);
      final vis = tester.widget<Visibility>(find.byType(Visibility));
      expect(vis.visible, isFalse);
      expect(vis.maintainSize, isTrue);

      final d2 = WorkoutDraft(
          id: d.id,
          date: d.date,
          exercises: [lift('Bench Press', 60, 9)]);
      // A refused submit returns at once; one that started would wait on the
      // held gate, so it is bounded (a hang is not a result).
      final second = await tester.runAsync(() => submitWorkoutDraft(d2, s.ref)
          .timeout(const Duration(seconds: 2),
              onTimeout: () => const DraftSubmitOutcome()));
      expect(second!.started, isFalse);

      await openGate(tester, gate, s);
      final sets = exlogFor('Bench Press')!['sets'] as List;
      expect(sets.map((x) => (x as Map)['reps']), everyElement(8));
      await waitReal(tester, kShortHold + const Duration(milliseconds: 100));
      sem.dispose();
      await done(tester);
    });
  });

  group('partial', () {
    testWidgets('Bench and Row save, X stays with the note; the day is marked '
        'once; the pencil has a tap action; a retry re-announces; a fix saves',
        (tester) async {
      await ensureHive(tester);
      final sem = tester.ensureSemantics();
      final s = await pumpSlot(tester, seed: draftOf([
        lift('Bench Press', 60, 8),
        bad('X'),
        lift('Row', 40, 10),
      ]));
      await confirm(tester, s);

      expect(exlogFor('Bench Press'), isNotNull);
      expect(exlogFor('Row'), isNotNull);
      expect(exlogFor('X'), isNull);
      expect(rows('wlog_'), hasLength(1), reason: 'partial marks the day');
      final wlog = Map.of(rows('wlog_').single);
      expect(s.draft!.exercises.map((e) => e.name), ['X']);
      expect(s.draft!.status, DraftCardStatus.partial);
      const note = 'Partly logged: Bench Press, Row. Not saved: X. '
          'Fix the sets or tap CONFIRM to retry.';
      expect(find.text(note), findsOneWidget);
      expect(find.text('set 1: 8 @ -5.0kg'), findsOneWidget);

      final pencil = tester.getSemantics(semanticsLabel('Edit X'));
      expect(pencil, isSemantics(isButton: true, hasTapAction: true));
      tester.semantics.tap(find.semantics.byLabel('Edit X'));
      await tester.pumpAndSettle();
      expect(find.text('Edit X'), findsOneWidget, reason: 'the sheet opened');
      await closeSheet(tester, 'Edit X');

      expect(find.byKey(const ValueKey('live_1')), findsOneWidget);
      await confirm(tester, s); // -5 still in place
      expect(s.draft!.failedAttempt, 2);
      expect(find.byKey(const ValueKey('live_2')), findsOneWidget);
      expect(find.byKey(const ValueKey('live_1')), findsNothing);

      await openSheetFor(tester, 0);
      await tester.enterText(find.byKey(const ValueKey('draft_weight_0')), '5');
      await tester.tap(find.text('SAVE CHANGES'));
      await tester.pumpAndSettle();
      expect(find.text(note), findsNothing, reason: 'an edit clears the note');
      expect(s.draft!.status, DraftCardStatus.partial);

      await confirm(tester, s);
      expect(s.draft!.status, DraftCardStatus.saved);
      expect(exlogFor('X'), isNotNull);
      expect(rows('wlog_'), hasLength(1));
      expect(rows('wlog_').single, wlog, reason: 'the retry does not rewrite it');
      await waitReal(tester, kShortHold + const Duration(milliseconds: 100));
      sem.dispose();
      await done(tester);
    });

    testWidgets('bodyweight with a bad weight: the sheet shows the weight '
        'field; 0 saves', (tester) async {
      await ensureHive(tester);
      final s = await pumpSlot(tester, seed: draftOf([
        DraftExercise(
            name: 'Pull-up',
            loggingType: 'bodyweight_reps',
            sets: [DraftSet(weightKg: -20, reps: 8)]),
      ]));
      await confirm(tester, s);
      expect(s.draft!.status, DraftCardStatus.noneSaved);
      await openSheetFor(tester, 0);
      expect(find.byKey(const ValueKey('draft_weight_0')), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('draft_weight_0')), '0');
      await tester.tap(find.text('SAVE CHANGES'));
      await tester.pumpAndSettle();
      await confirm(tester, s);
      expect(s.draft!.status, DraftCardStatus.saved);
      expect(exlogFor('Pull-up'), isNotNull);
      await waitReal(tester, kShortHold + const Duration(milliseconds: 100));
      await done(tester);
    });

    testWidgets('none saved: the box is closed, every exercise is kept with '
        'the none-saved note', (tester) async {
      await ensureHive(tester);
      final s = await pumpSlot(tester, seed: draftOf([
        lift('Bench Press', 60, 8),
        lift('Row', 40, 10),
      ]));
      await tester.runAsync(() => box.close());
      await confirm(tester, s);
      await tester.runAsync(() => Hive.openBox(HiveUserSession.namespacedBoxName(
          HiveService.workoutBoxName, kTestUserId)));
      expect(s.draft!.status, DraftCardStatus.noneSaved);
      expect(find.text(WardroomCopy.coachWorkoutLogFailed), findsOneWidget);
      expect(s.draft!.exercises.map((e) => e.name), ['Bench Press', 'Row']);
      expect(rows('exlog_'), isEmpty);
      await done(tester);
    });

    testWidgets('cumulative save memory: a retry keeps every saved name and '
        'DISCARD asks first; an edit keeps the partial status',
        (tester) async {
      await ensureHive(tester);
      final s = await pumpSlot(tester, seed: draftOf([
        lift('Bench Press', 60, 8),
        bad('X'),
        lift('Row', 40, 10),
      ]));
      await confirm(tester, s);
      await confirm(tester, s);
      const note = 'Partly logged: Bench Press, Row. Not saved: X. '
          'Fix the sets or tap CONFIRM to retry.';
      expect(find.text(note), findsOneWidget);
      expect(s.draft!.savedNames, ['Bench Press', 'Row']);

      s.n.updateSet(s.draft!.id, 0, 0, DraftSet(weightKg: -6, reps: 8));
      await tester.pump();
      expect(s.draft!.status, DraftCardStatus.partial);
      await tester.tap(find.text('DISCARD'));
      await tester.pump();
      expect(find.text('Discard the rest? Bench Press, Row stay logged.'),
          findsOneWidget);
      expect(s.draft, isNotNull, reason: 'DISCARD after a save asks first');
      await done(tester);
    });

    testWidgets('discard after partial: the line for one saved name; KEEP '
        'restores the buttons; DISCARD discards', (tester) async {
      await ensureHive(tester);
      final s = await pumpSlot(tester,
          seed: draftOf([lift('Bench Press', 60, 8), bad('X')]));
      await confirm(tester, s);
      await tester.tap(find.text('DISCARD'));
      await tester.pump();
      expect(find.text('Discard the rest? Bench Press stays logged.'),
          findsOneWidget);
      await tester.tap(find.text(WardroomCopy.coachWorkoutKeepLabel));
      await tester.pump();
      expect(find.text(kConfirm), findsOneWidget);
      await tester.tap(find.text('DISCARD'));
      await tester.pump();
      await tester.tap(find.text('DISCARD'));
      await tester.pump();
      expect(s.draft, isNull);
      await done(tester);
    });
  });

  group('day not marked, skipped, cardio', () {
    testWidgets('a timed set with a bad duration saves, the day mark fails: '
        'the day line, no wlog_, the long hold', (tester) async {
      await ensureHive(tester);
      final s = await pumpSlot(tester, seed: draftOf([badPlank()]));
      await confirm(tester, s);
      expect(s.draft!.status, DraftCardStatus.savedDayNotMarked);
      expect(find.text(WardroomCopy.coachWorkoutLoggedHeader), findsOneWidget);
      expect(find.text(WardroomCopy.coachWorkoutDayNotMarked), findsOneWidget);
      expect(rows('exlog_'), hasLength(1));
      expect(rows('wlog_'), isEmpty);
      // OI-382: the long hold, so the line can be read.
      await waitReal(tester, kShortHold + const Duration(milliseconds: 100));
      expect(s.draft, isNotNull);
      await waitReal(tester, kLongHold);
      expect(s.draft, isNull);
      await done(tester);
    });

    testWidgets('already-done day: wlog_ is not overwritten, no day line',
        (tester) async {
      await ensureHive(tester);
      final today = istDateStr(DateTime.now());
      final pushDay = {
        'type': 'workout_log',
        'workout_name': 'Push Day',
        'date': today,
        'duration_seconds': 1800,
        'rpe': 8,
      };
      await tester.runAsync(() async {
        await box.put('schedule_$today', {
          'date': today,
          'workout_name': 'Push Day',
          'type': 'workout',
          'status': 'completed',
        });
        await box.put('wlog_$today', pushDay);
      });
      final s = await pumpSlot(tester,
          seed: draftOf([lift('Bench Press', 60, 8)]));
      await confirm(tester, s);
      expect(s.draft!.status, DraftCardStatus.saved);
      expect(find.text(WardroomCopy.coachWorkoutDayNotMarked), findsNothing);
      expect(Map.of(box.get('wlog_$today') as Map), pushDay);
      await waitReal(tester, kShortHold + const Duration(milliseconds: 100));
      await done(tester);
    });

    testWidgets('a completed status with no wlog_ still gets its wlog_',
        (tester) async {
      // B-pass fb5048e68fae F5: the already-done gate needs BOTH records;
      // a restored "completed" day whose wlog_ never synced gets one, as on
      // origin/main.
      await ensureHive(tester);
      final today = istDateStr(DateTime.now());
      await tester.runAsync(() async {
        await box.put('schedule_$today', {
          'date': today,
          'workout_name': 'Push Day',
          'type': 'workout',
          'status': 'completed',
        });
      });
      final s = await pumpSlot(tester,
          seed: draftOf([lift('Bench Press', 60, 8)]));
      await confirm(tester, s);
      expect(s.draft!.status, DraftCardStatus.saved);
      expect(rows('wlog_'), hasLength(1));
      await waitReal(tester, kShortHold + const Duration(milliseconds: 100));
      await done(tester);
    });

    testWidgets('a retry that saves nothing new but marks the day refreshes '
        'the workout surfaces', (tester) async {
      // B-pass fb5048e68fae F1: attempt 1 saves Plank, X fails, the mark
      // fails (negative duration); attempt 2, unchanged, saves nothing but
      // marks the day, so Train's done-day reads change and must refresh.
      await ensureHive(tester);
      final log = DisposeLog();
      final s = await pumpSlot(tester,
          seed: draftOf([badPlank(), bad('X')]), observers: [log]);
      await confirm(tester, s);
      expect(s.draft!.status, DraftCardStatus.partial);
      expect(s.draft!.dayNotMarked, isTrue);
      expect(rows('wlog_'), isEmpty);
      s.c.read(lastPerformanceProvider('X'));
      log.disposed.clear();
      await confirm(tester, s);
      expect(s.draft!.status, DraftCardStatus.partial);
      expect(s.draft!.dayNotMarked, isFalse);
      expect(rows('wlog_'), hasLength(1));
      expect(log.disposed.where((p) => p.from == lastPerformanceProvider),
          isNotEmpty,
          reason: 'the day mark refreshes the workout surfaces');
      await done(tester);
    });

    testWidgets('a retry that saves nothing and marks nothing refreshes '
        'nothing', (tester) async {
      // The mirror of the case above: no new write, no refresh.
      await ensureHive(tester);
      final log = DisposeLog();
      final s = await pumpSlot(tester,
          seed: draftOf([lift('Bench Press', 60, 8), bad('X')]),
          observers: [log]);
      await confirm(tester, s);
      expect(s.draft!.status, DraftCardStatus.partial);
      expect(s.draft!.dayNotMarked, isFalse);
      s.c.read(lastPerformanceProvider('X'));
      log.disposed.clear();
      await confirm(tester, s);
      expect(log.disposed.where((p) => p.from == lastPerformanceProvider),
          isEmpty);
      await done(tester);
    });

    testWidgets('skipped leftover: saved with the Skipped line in the live '
        'region, the long hold, no note, one wlog_', (tester) async {
      await ensureHive(tester);
      final sem = tester.ensureSemantics();
      final s = await pumpSlot(tester,
          seed: draftOf([lift('Bench Press', 60, 8), emptyPlank()]));
      await confirm(tester, s);
      expect(s.draft!.status, DraftCardStatus.saved);
      expect(liveNode(tester),
          isSemantics(
              isLiveRegion: true,
              label: 'WORKOUT LOGGED\nSkipped: Plank (no usable sets).'));
      expect(find.text(kConfirm), findsNothing);
      expect(find.textContaining('Partly logged'), findsNothing);
      expect(rows('wlog_'), hasLength(1));
      await waitReal(tester, kShortHold + const Duration(milliseconds: 100));
      expect(s.draft, isNotNull, reason: 'the long hold');
      await waitReal(tester, kLongHold);
      sem.dispose();
      await done(tester);
    });

    testWidgets('unusable sets are skipped, not kept', (tester) async {
      await ensureHive(tester);
      final s = await pumpSlot(tester, seed: draftOf([
        lift('Bench Press', 60, 8),
        DraftExercise(
            name: 'X', loggingType: 'weight_reps', sets: [DraftSet(reps: -3)]),
      ]));
      await confirm(tester, s);
      expect(s.draft!.status, DraftCardStatus.saved);
      expect(find.text('Skipped: X (no usable sets).'), findsOneWidget);
      expect(find.text('X'), findsNothing, reason: 'X is not a card row');
      await waitReal(tester, kLongHold + const Duration(milliseconds: 100));
      await done(tester);
    });

    testWidgets('cardio with a duration is logged, not skipped',
        (tester) async {
      await ensureHive(tester);
      final s = await pumpSlot(tester, seed: draftOf([
        lift('Bench Press', 60, 8),
        DraftExercise(
            name: 'Run', loggingType: 'cardio', sets: [], durationMins: 20),
      ]));
      await confirm(tester, s);
      expect(s.draft!.status, DraftCardStatus.saved);
      expect(exlogFor('Run'), isNotNull);
      expect(find.textContaining('Skipped'), findsNothing);
      await waitReal(tester, kShortHold + const Duration(milliseconds: 100));
      await done(tester);
    });

    testWidgets('skipped survives a retry', (tester) async {
      await ensureHive(tester);
      final s = await pumpSlot(tester, seed: draftOf([
        lift('Bench Press', 60, 8),
        bad('X'),
        emptyPlank(),
      ]));
      await confirm(tester, s);
      expect(
          find.text('Partly logged: Bench Press. Not saved: X. '
              'Fix the sets or tap CONFIRM to retry.'),
          findsOneWidget);
      expect(find.text('Skipped: Plank (no usable sets).'), findsOneWidget);
      s.n.updateSet(s.draft!.id, 0, 0, DraftSet(weightKg: 5, reps: 8));
      await tester.pump();
      await confirm(tester, s);
      expect(s.draft!.status, DraftCardStatus.saved);
      expect(find.text('Skipped: Plank (no usable sets).'), findsOneWidget);
      await waitReal(tester, kLongHold + const Duration(milliseconds: 100));
      await done(tester);
    });

    testWidgets('partial with the day not marked: the line stays through an '
        'edit and goes once a retry marks the day', (tester) async {
      await ensureHive(tester);
      final sem = tester.ensureSemantics();
      final s = await pumpSlot(tester, seed: draftOf([badPlank(), bad('X')]));
      await confirm(tester, s);
      expect(s.draft!.status, DraftCardStatus.partial);
      expect(s.draft!.dayNotMarked, isTrue);
      expect(liveNode(tester).label,
          startsWith('${WardroomCopy.coachWorkoutDayNotMarked}\nPartly logged'));
      s.n.updateSet(s.draft!.id, 0, 0, DraftSet(weightKg: 5, reps: 8));
      await tester.pump();
      expect(find.text(WardroomCopy.coachWorkoutDayNotMarked), findsOneWidget);
      await confirm(tester, s);
      expect(s.draft!.status, DraftCardStatus.saved);
      expect(find.text(WardroomCopy.coachWorkoutDayNotMarked), findsNothing);
      expect(rows('wlog_'), hasLength(1));
      await waitReal(tester, kShortHold + const Duration(milliseconds: 100));
      sem.dispose();
      await done(tester);
    });
  });

  group('held draft', () {
    testWidgets('(a) a card arriving mid-submit waits for the saved hold, '
        'then appears and is announced once', (tester) async {
      await ensureHive(tester);
      final announced = <String>[];
      tester.binding.defaultBinaryMessenger.setMockDecodedMessageHandler<dynamic>(
          SystemChannels.accessibility, (msg) async {
        if (msg is Map && msg['type'] == 'announce') {
          announced.add((msg['data'] as Map)['message'] as String);
        }
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockDecodedMessageHandler<dynamic>(
              SystemChannels.accessibility, null));
      final s = await pumpSlot(tester,
          seed: draftOf([lift('Bench Press', 60, 8)]), fillers: 8);
      final gate = DraftSubmitDebug.debugSubmitGate = Completer<void>();
      await tester.runAsync(() => tester.tap(find.text(kConfirm)));
      await tester.pump();
      s.n.setDraft(coachData('Squat'));
      await tester.pump();
      expect(s.draft!.id, 'wdraft_a', reason: 'B is held');
      await openGate(tester, gate, s);
      expect(s.draft!.status, DraftCardStatus.saved);
      expect(find.text('Squat'), findsNothing);
      await waitReal(tester, kShortHold + const Duration(milliseconds: 100));
      expect(find.text('Squat'), findsOneWidget);
      expect(announced, ['Workout ready to log']);
      expect(s.draft!.appliedFromHold, isFalse);

      // Out of view and back: no second announcement.
      await tester.drag(find.byType(ListView), const Offset(0, -3000));
      await tester.pumpAndSettle();
      expect(find.text('Squat'), findsNothing);
      await tester.drag(find.byType(ListView), const Offset(0, 3000));
      await tester.pumpAndSettle();
      expect(find.text('Squat'), findsOneWidget);
      expect(announced, hasLength(1));
      await done(tester);
    });

    testWidgets('(b) held behind a partial: the notice shows; DISCARD, '
        'confirm, DISCARD shows the held card', (tester) async {
      await ensureHive(tester);
      final sem = tester.ensureSemantics();
      final s = await pumpSlot(tester,
          seed: draftOf([lift('Bench Press', 60, 8), bad('X')]));
      await confirm(tester, s);
      s.n.setDraft(coachData('Squat'));
      await tester.pump();
      expect(find.text(WardroomCopy.coachWorkoutHeldNotice), findsOneWidget);
      expect(liveNode(tester).label,
          startsWith('${WardroomCopy.coachWorkoutHeldNotice}\nPartly logged'));
      await tester.tap(find.text('DISCARD'));
      await tester.pump();
      expect(find.text('Squat'), findsNothing);
      await tester.tap(find.text('DISCARD'));
      await tester.pump();
      expect(find.text('Squat'), findsOneWidget);
      expect(find.text(WardroomCopy.coachWorkoutHeldNotice), findsNothing);
      sem.dispose();
      await done(tester);
    });

    testWidgets('(c) KEEP restores the held-behind card', (tester) async {
      await ensureHive(tester);
      final s = await pumpSlot(tester,
          seed: draftOf([lift('Bench Press', 60, 8), bad('X')]));
      await confirm(tester, s);
      s.n.setDraft(coachData('Squat'));
      await tester.pump();
      await tester.tap(find.text('DISCARD'));
      await tester.pump();
      await tester.tap(find.text(WardroomCopy.coachWorkoutKeepLabel));
      await tester.pump();
      expect(find.text(kConfirm), findsOneWidget);
      expect(find.text('X'), findsOneWidget);
      expect(find.text(WardroomCopy.coachWorkoutHeldNotice), findsOneWidget);
      await done(tester);
    });

    testWidgets('(f) the card applied after "Discard the rest" ignores CONFIRM '
        'for its first moment', (tester) async {
      // B-pass fb5048e68fae F4: the second tap of a double tap on the wide
      // left "Discard the rest" lands where the new card's CONFIRM is.
      await ensureHive(tester);
      final s = await pumpSlot(tester,
          seed: draftOf([lift('Bench Press', 60, 8), bad('X')]));
      await confirm(tester, s);
      s.n.setDraft(coachData('Squat'));
      await tester.pump();
      await tester.tap(find.text('DISCARD'));
      await tester.pump();
      await tester.tap(find.text('DISCARD'));
      await tester.pump();
      expect(find.text('Squat'), findsOneWidget);
      // tapWrite runs the tap in real time, so without the guard the write
      // completes (and this fails) instead of hanging in fake time.
      await tapWrite(tester, s, find.text(kConfirm));
      expect(s.draft!.isSubmitting, isFalse);
      expect(exlogFor('Squat'), isNull, reason: 'the immediate tap is ignored');
      await waitReal(tester, kHeldCardTapGuard + const Duration(milliseconds: 100));
      await confirm(tester, s);
      expect(s.draft!.status, DraftCardStatus.saved);
      expect(exlogFor('Squat'), isNotNull);
      await waitReal(tester, kShortHold + const Duration(milliseconds: 100));
      await done(tester);
    });

    testWidgets('(d) two arrivals while held: only the latest applies',
        (tester) async {
      await ensureHive(tester);
      final s = await pumpSlot(tester,
          seed: draftOf([lift('Bench Press', 60, 8), bad('X')]));
      await confirm(tester, s);
      s.n.setDraft(coachData('Squat'));
      s.n.setDraft(coachData('Deadlift'));
      s.n.discard();
      await tester.pump();
      expect(find.text('Deadlift'), findsOneWidget);
      expect(find.text('Squat'), findsNothing);
      await done(tester);
    });

    testWidgets('(e) a partial the user edited still holds a new card',
        (tester) async {
      await ensureHive(tester);
      final s = await pumpSlot(tester,
          seed: draftOf([lift('Bench Press', 60, 8), bad('X')]));
      await confirm(tester, s);
      s.n.updateSet(s.draft!.id, 0, 0, DraftSet(weightKg: 5, reps: 8));
      s.n.setDraft(coachData('Squat'));
      await tester.pump();
      expect(s.draft!.id, 'wdraft_a');
      expect(find.text(WardroomCopy.coachWorkoutHeldNotice), findsOneWidget);
      await done(tester);
    });

    testWidgets('held during a submit that ends partial: the notice shows',
        (tester) async {
      await ensureHive(tester);
      final s = await pumpSlot(tester,
          seed: draftOf([lift('Bench Press', 60, 8), bad('X')]));
      final gate = DraftSubmitDebug.debugSubmitGate = Completer<void>();
      await tester.runAsync(() => tester.tap(find.text(kConfirm)));
      await tester.pump();
      s.n.setDraft(coachData('Squat'));
      await tester.pump();
      expect(find.text(WardroomCopy.coachWorkoutHeldNotice), findsNothing,
          reason: 'not while submitting');
      await openGate(tester, gate, s);
      expect(s.draft!.status, DraftCardStatus.partial);
      expect(find.text(WardroomCopy.coachWorkoutHeldNotice), findsOneWidget);
      await done(tester);
    });
  });

  group('id guards and auth', () {
    testWidgets('auth flip mid-submit: nothing is written', (tester) async {
      await ensureHive(tester);
      final s = await pumpSlot(tester,
          seed: draftOf([lift('Bench Press', 60, 8)]));
      final gate = DraftSubmitDebug.debugSubmitGate = Completer<void>();
      await tester.runAsync(() => tester.tap(find.text(kConfirm)));
      await tester.pump();
      s.flipAuth('v');
      expect(s.draft, isNull);
      await openGate(tester, gate, s);
      expect(rows('exlog_'), isEmpty);
      expect(rows('wlog_'), isEmpty);
      expect(rows('schedule_'), isEmpty);
      await done(tester);
    });

    testWidgets('auth flip on a retry, after the writes: no day mark',
        (tester) async {
      await ensureHive(tester);
      final s = await pumpSlot(tester,
          seed: WorkoutDraft(
            id: 'wdraft_r',
            date: DateTime.now(),
            exercises: [bad('X')],
            status: DraftCardStatus.partial,
            savedNames: const ['Bench Press'],
            failedAttempt: 1,
            note: formatDraftNote(
                savedNames: const ['Bench Press'], failedNames: const ['X']),
          ));
      s.n.updateSet('wdraft_r', 0, 0, DraftSet(weightKg: 5, reps: 8));
      await tester.pump();
      final markGate =
          DraftSubmitDebug.debugBeforeMarkGate = Completer<void>();
      await tester.runAsync(() async {
        await tester.tap(find.text(kConfirm));
        for (var i = 0; i < 250 && exlogFor('X') == null; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      });
      expect(exlogFor('X'), isNotNull);
      s.flipAuth('v');
      await openGate(tester, markGate, s);
      expect(exlogFor('X'), isNotNull);
      expect(rows('wlog_'), isEmpty);
      expect(rows('schedule_'), isEmpty);
      await done(tester);
    });

    testWidgets('draft-id guard via auth: a new card after the flip is not '
        'shown as saved', (tester) async {
      await ensureHive(tester);
      final s = await pumpSlot(tester,
          seed: draftOf([lift('Bench Press', 60, 8)]));
      final gate = DraftSubmitDebug.debugSubmitGate = Completer<void>();
      await tester.runAsync(() => tester.tap(find.text(kConfirm)));
      await tester.pump();
      s.flipAuth('v');
      s.n.setDraft(coachData('Squat'));
      await tester.pump();
      await openGate(tester, gate, s);
      expect(s.draft!.status, DraftCardStatus.pending);
      expect(find.text('Workout ready to log'), findsOneWidget);
      expect(find.text(kConfirm), findsOneWidget);
      await done(tester);
    });

    testWidgets('id guards, direct: every write with a stale id changes '
        'nothing', (tester) async {
      await ensureHive(tester);
      final b = WorkoutDraft(
        id: 'wdraft_b',
        date: DateTime.now(),
        exercises: [lift('Squat', 80, 5)],
        appliedFromHold: true,
      );
      final c = ProviderContainer(overrides: [
        authUserIdTokenProvider.overrideWithValue('u'),
        workoutDraftProvider.overrideWith(() => SeededWorkoutDraftNotifier(b)),
      ]);
      addTearDown(c.dispose);
      late WidgetRef ref;
      // No card: the card would consume the announcement.
      await tester.pumpWidget(UncontrolledProviderScope(
        container: c,
        child: MaterialApp(home: Consumer(builder: (context, r, _) {
          ref = r;
          return const SizedBox.shrink();
        })),
      ));
      final n = c.read(workoutDraftProvider.notifier);
      var before = c.read(workoutDraftProvider);
      n.updateSet('wdraft_a', 0, 0, DraftSet(weightKg: 1, reps: 1));
      expect(identical(c.read(workoutDraftProvider), before), isTrue);

      final gate = DraftSubmitDebug.debugSubmitGate = Completer<void>();
      late Future<DraftSubmitOutcome> f;
      await tester.runAsync(() async {
        f = submitWorkoutDraft(b, ref);
        await Future<void>.delayed(Duration.zero);
      });
      before = c.read(workoutDraftProvider);
      expect(before!.isSubmitting, isTrue);
      expect(before.appliedFromHold, isTrue);
      n.markSaved('wdraft_a', dayMarked: true);
      expect(identical(c.read(workoutDraftProvider), before), isTrue);
      n.keepFailed('wdraft_a', const [0], const [], dayMarked: true);
      expect(identical(c.read(workoutDraftProvider), before), isTrue);
      n.endSubmit('wdraft_a');
      expect(identical(c.read(workoutDraftProvider), before), isTrue);
      n.consumeHoldAnnouncement('wdraft_a');
      expect(identical(c.read(workoutDraftProvider), before), isTrue);
      await tester.runAsync(() async {
        gate.complete();
        await f;
      });
      // A saved card refuses a new submit (B-pass fb5048e68fae PM6).
      final savedB = c.read(workoutDraftProvider)!;
      expect(savedB.status, DraftCardStatus.saved);
      expect(n.beginSubmit('wdraft_b', DateTime.now()), isNull);
      expect(identical(c.read(workoutDraftProvider), savedB), isTrue);
      await done(tester);
    });

    testWidgets('the draft notifier survives an auth rebuild (the captured '
        'notifier depends on it)', (tester) async {
      // B-pass fb5048e68fae F7: submitWorkoutDraft and the edit sheet hold
      // the notifier across awaits. Riverpod 3.2.1 reuses the instance and
      // reruns build(); a version that mints a new one must fail here first.
      await ensureHive(tester);
      final s = await pumpSlot(tester,
          seed: draftOf([lift('Bench Press', 60, 8)]));
      final before = s.n;
      s.flipAuth('v');
      expect(identical(before, s.n), isTrue);
      expect(s.draft, isNull, reason: 'build() reset the state');
      await done(tester);
    });

    testWidgets('retry after IST midnight writes to the first attempt\'s day',
        (tester) async {
      await ensureHive(tester);
      DraftSubmitDebug.clock = () => DateTime(2026, 10, 20, 23, 59);
      final s = await pumpSlot(tester,
          seed: draftOf([lift('Bench Press', 60, 8), bad('X')]));
      await confirm(tester, s);
      expect(s.draft!.status, DraftCardStatus.partial);
      DraftSubmitDebug.clock = () => DateTime(2026, 10, 21, 0, 5);
      s.n.updateSet(s.draft!.id, 0, 0, DraftSet(weightKg: 5, reps: 8));
      await tester.pump();
      await confirm(tester, s);
      expect(exlogFor('X')!['date'], '2026-10-20');
      expect(box.get('wlog_2026-10-20'), isNotNull);
      expect(box.get('wlog_2026-10-21'), isNull);
      expect(rows('exlog_').where((r) => r['date'] == '2026-10-21'), isEmpty);
      await waitReal(tester, kShortHold + const Duration(milliseconds: 100));
      await done(tester);
    });

    testWidgets('stale edit sheet: saving it after a new card changes nothing',
        (tester) async {
      await ensureHive(tester);
      final s = await pumpSlot(tester, seed: draftOf([bad('X')]));
      await openSheetFor(tester, 0);
      s.n.setDraft({
        'exercises': [
          {
            'name': 'Squat',
            'logging_type': 'weight_reps',
            'sets': [
              {'weight_kg': 80, 'reps': 5},
              {'weight_kg': 80, 'reps': 5},
            ],
          },
        ],
      });
      await tester.pump();
      final b = s.draft;
      expect(b!.exercises.single.name, 'Squat');
      await tester.enterText(find.byKey(const ValueKey('draft_weight_0')), '7');
      await tester.tap(find.text('SAVE CHANGES'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(identical(s.draft, b), isTrue);
      await done(tester);
    });

    testWidgets('timer cancel: discard during the hold, and an auth flip',
        (tester) async {
      await ensureHive(tester);
      var s = await pumpSlot(tester,
          seed: draftOf([lift('Bench Press', 60, 8)]));
      await confirm(tester, s);
      expect(s.n.hasPendingClear, isTrue);
      s.n.discard();
      expect(s.n.hasPendingClear, isFalse);
      await done(tester);

      await ensureHive(tester);
      s = await pumpSlot(tester, seed: draftOf([lift('Row', 40, 10)]));
      await confirm(tester, s);
      final n = s.n;
      expect(n.hasPendingClear, isTrue);
      s.flipAuth('v');
      expect(n.hasPendingClear, isFalse);
      await done(tester);
    });
  });

  group('TalkBack', () {
    testWidgets('button labels, the confirm row line as a live region',
        (tester) async {
      await ensureHive(tester);
      final sem = tester.ensureSemantics();
      final s = await pumpSlot(tester,
          seed: draftOf([lift('Bench Press', 60, 8), bad('X'), lift('Row', 40, 10)]));
      expect(
          tester.getSemantics(
              semanticsLabel(WardroomCopy.coachWorkoutConfirmSemantics)),
          isSemantics(isButton: true, isEnabled: true, hasTapAction: true));
      expect(
          tester.getSemantics(
              semanticsLabel(WardroomCopy.coachWorkoutDiscardSemantics)),
          isSemantics(isButton: true, isEnabled: true, hasTapAction: true));
      await confirm(tester, s);
      await tester.tap(find.text('DISCARD'));
      await tester.pump();
      expect(
          tester.getSemantics(
              semanticsLabel(WardroomCopy.coachWorkoutDiscardRestSemantics)),
          isSemantics(isButton: true, hasTapAction: true));
      expect(
          tester.getSemantics(
              semanticsLabel(WardroomCopy.coachWorkoutKeepSemantics)),
          isSemantics(isButton: true, hasTapAction: true));
      expect(
          tester.getSemantics(semanticsLabel(
              'Discard the rest? Bench Press, Row stay logged.')),
          isSemantics(isLiveRegion: true));
      sem.dispose();
      await done(tester);
    });
  });

  group('input', () {
    final w = DraftSetInputFormatter(decimal: true);
    final r = DraftSetInputFormatter(decimal: false);
    TextEditingValue v(String t) =>
        TextEditingValue(text: t, selection: TextSelection.collapsed(offset: t.length));
    String fmt(DraftSetInputFormatter f, String a, String b) =>
        f.formatEditUpdate(v(a), v(b)).text;

    test('rejects, never trims', () {
      expect(fmt(w, '12.5', '12.5.'), '12.5');
      expect(fmt(w, '12.5', '12.5-'), '12.5');
      expect(fmt(r, '8', '8.5'), '8');
      expect(fmt(w, '12', '12,'), '12.');
      expect(fmt(w, '12.5', 'a'), '12.5', reason: 'a paste over a selection');
      expect(fmt(w, '12.5', ''), '', reason: 'clearing is allowed');
    });

    test('guard cases', () {
      expect(fmt(w, '', '5'), '5');
      expect(fmt(w, '', 'a'), '');
      expect(fmt(w, '-', '--'), '-');
      expect(fmt(w, '1', '11'), '11');
      final composing = TextEditingValue(
          text: '-5.0',
          selection: const TextSelection.collapsed(offset: 4),
          composing: const TextRange(start: 0, end: 4));
      expect(w.formatEditUpdate(v('-5.0'), composing), composing);
    });

    testWidgets('backspace walks a seeded negative down to empty',
        (tester) async {
      await ensureHive(tester);
      await pumpSlot(tester, seed: draftOf([
        DraftExercise(
            name: 'X',
            loggingType: 'weight_reps',
            sets: [DraftSet(weightKg: -5, reps: -3)]),
      ]));
      await openSheetFor(tester, 0);
      final weight = find.byKey(const ValueKey('draft_weight_0'));
      final reps = find.byKey(const ValueKey('draft_reps_0'));
      String text(Finder f) => tester.widget<TextField>(f).controller!.text;
      expect(text(weight), '-5.0');
      await tester.showKeyboard(weight);
      for (final t in ['-5.', '-5', '-', '']) {
        tester.testTextInput.updateEditingValue(v(t));
        await tester.pump();
        expect(text(weight), t);
      }
      await tester.showKeyboard(reps);
      expect(text(reps), '-3');
      for (final t in ['-', '']) {
        tester.testTextInput.updateEditingValue(v(t));
        await tester.pump();
        expect(text(reps), t);
      }
      await closeSheet(tester, 'Edit X');
      await done(tester);
    });
  });

  group('pure', () {
    test('names: five then +N more, de-duplicated; Not saved names failures only',
        () {
      expect(joinDraftNames(['A', 'B', 'C', 'D', 'E', 'F', 'G']),
          'A, B, C, D, E +2 more');
      expect(joinDraftNames(['A', 'B', 'A']), 'A, B');
      expect(formatDraftNote(savedNames: ['Bench'], failedNames: ['X']),
          'Partly logged: Bench. Not saved: X. Fix the sets or tap CONFIRM to retry.');
      expect(formatDraftNote(savedNames: const [], failedNames: ['X']),
          WardroomCopy.coachWorkoutLogFailed);
      expect(formatDiscardRest(['Bench', 'Bench']),
          'Discard the rest? Bench stays logged.');
      expect(formatSkipped(['Plank']), 'Skipped: Plank (no usable sets).');
    });

    test('cardStateFor truth table', () {
      WorkoutDraft d(DraftCardStatus st, {bool sub = false}) => WorkoutDraft(
          id: 'x', exercises: const [], date: DateTime(2026),
          status: st, isSubmitting: sub);
      expect(cardStateFor(d(DraftCardStatus.pending)), WorkoutCardState.pending);
      expect(cardStateFor(d(DraftCardStatus.saved)), WorkoutCardState.saved);
      expect(cardStateFor(d(DraftCardStatus.savedDayNotMarked)),
          WorkoutCardState.savedDayNotMarked);
      expect(cardStateFor(d(DraftCardStatus.partial)), WorkoutCardState.partial);
      expect(cardStateFor(d(DraftCardStatus.noneSaved)),
          WorkoutCardState.noneSaved);
      for (final st in DraftCardStatus.values) {
        expect(cardStateFor(d(st, sub: true)), WorkoutCardState.submitting);
      }
    });

    test('scroll truth table: only a new card scrolls', () {
      final a = draftOf(const [], id: 'a');
      final a2 = a.copyWith(status: DraftCardStatus.saved);
      final b = draftOf(const [], id: 'b');
      expect(workoutDraftChangeScrolls(null, a), isTrue);
      expect(workoutDraftChangeScrolls(a, a2), isFalse);
      expect(workoutDraftChangeScrolls(a, b), isTrue);
      expect(workoutDraftChangeScrolls(a, null), isFalse);
      expect(workoutDraftChangeScrolls(null, null), isFalse);
      expect(hasWorkoutDraftSlot(null), isFalse);
      expect(hasWorkoutDraftSlot(a), isTrue);
    });

    test('pins: the chat uses the slot and the scroll rule', () {
      final chat = File(
              'lib/features/ai_coach/screens/ai_coach/chat_area.dart')
          .readAsStringSync();
      expect(chat, contains('const WorkoutDraftSlot()'));
      expect(chat, contains('hasWorkoutDraftSlot('));
      final screen = File('lib/features/ai_coach/screens/ai_coach/screen.dart')
          .readAsStringSync();
      expect(screen, contains('workoutDraftChangeScrolls(prev, next)'),
          reason: 'argument order (B-pass fb5048e68fae F11)');
    });
  });

  group('large text', () {
    for (final scale in [1.0, 1.3, 1.5, 2.0]) {
      testWidgets('320 dp at $scale: no exception; stacked from 1.5',
          (tester) async {
        await ensureHive(tester);
        final sem = tester.ensureSemantics();
        await pumpSlot(tester,
            seed: draftOf([lift('Bench Press', 60, 8)]),
            scale: scale,
            width: 320);
        expect(tester.takeException(), isNull);
        final c = tester.getRect(
            semanticsLabel(WardroomCopy.coachWorkoutConfirmSemantics));
        final d = tester.getRect(
            semanticsLabel(WardroomCopy.coachWorkoutDiscardSemantics));
        if (scale >= 1.5) {
          expect(c.bottom, lessThanOrEqualTo(d.top), reason: 'stacked');
        } else {
          expect(c.right, lessThanOrEqualTo(d.left), reason: 'one row');
        }
        sem.dispose();
        await done(tester);
      });
    }

    for (final scale in [1.0, 1.5, 2.0]) {
      testWidgets('320 dp at $scale: the second tap of a double tap on DISCARD '
          'never lands on "Discard the rest"', (tester) async {
        // B-pass fb5048e68fae F3 (founder rule, plan §2): a quick double tap
        // on DISCARD keeps the card. Measured: the question line pushes the
        // confirm row down, so the old DISCARD centre is on that inert line.
        await ensureHive(tester);
        final sem = tester.ensureSemantics();
        final s = await pumpSlot(tester,
            seed: draftOf([lift('Bench Press', 60, 8), bad('X')]),
            scale: scale,
            width: 320);
        await confirm(tester, s);
        expect(s.draft!.status, DraftCardStatus.partial);
        final before = tester.getRect(
            semanticsLabel(WardroomCopy.coachWorkoutDiscardSemantics));
        await tester.tap(find.text('DISCARD'));
        await tester.pump();
        final keep = tester
            .getRect(semanticsLabel(WardroomCopy.coachWorkoutKeepSemantics));
        final rest = tester.getRect(
            semanticsLabel(WardroomCopy.coachWorkoutDiscardRestSemantics));
        expect(rest.contains(before.center), isFalse,
            reason: '"Discard the rest" is not under the finger');
        expect(keep.top, greaterThanOrEqualTo(rest.top),
            reason: 'KEEP is right of or below "Discard the rest"');
        await tester.tapAt(before.center);
        await tester.pump();
        expect(s.draft, isNotNull, reason: 'the second tap kept the card');
        expect(s.draft!.savedNames, ['Bench Press']);
        sem.dispose();
        await done(tester);
      });
    }

    for (final scale in [1.0, 1.3, 2.0]) {
      testWidgets('densest state at 320 dp × $scale: no overflow, no clipped '
          'line', (tester) async {
        await ensureHive(tester);
        const saved = ['Bench Press', 'Row', 'Squat', 'Deadlift', 'Lunge'];
        const failed = ['Curl', 'Press', 'Dip', 'Fly', 'Shrug'];
        await pumpSlot(tester,
            width: 320,
            scale: scale,
            seed: WorkoutDraft(
              id: 'wdraft_dense',
              date: DateTime.now(),
              exercises: [for (final f in failed) bad(f)],
              status: DraftCardStatus.partial,
              savedNames: saved,
              skippedNames: const ['Plank', 'Side Plank'],
              failedAttempt: 1,
              hasHeldDraft: true,
              note: formatDraftNote(savedNames: saved, failedNames: failed),
            ));
        expect(tester.takeException(), isNull);
        final paragraphs = tester
            .renderObjectList<RenderParagraph>(find.descendant(
                of: find.byType(WorkoutLogConfirmCard),
                matching: find.byType(RichText)))
            .toList();
        expect(paragraphs, isNotEmpty);
        for (final p in paragraphs) {
          expect(p.didExceedMaxLines, isFalse, reason: p.text.toPlainText());
        }
        await done(tester);
      });
    }
  });
}
