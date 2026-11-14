// The flip through the REAL `ActiveWorkoutScreen` (docs/plans/
// log-exercise-flip.md §6 S1, SM2): the flag absent means LOG mode; a stored
// `false` brings the per-set path back on the next build; FINISH names what
// will not be saved; the header counts working sets; RE-OPEN is announced.
@Timeout(Duration(minutes: 4))
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/copy/wardroom_copy.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/features/train/services/log_exercise_flags.dart';

import '../../../helpers/dart_source_slice.dart';
import 'card_harness.dart';

void main() {
  tearDownAll(closeHive);

  testWidgets('fonts degrade before any Hive mock', renderFontsFirst);

  testWidgets('S1: flag absent = LOG mode; a stored false brings the per-set '
      'path back on the next build', (tester) async {
    final h = await pumpScreen(tester,
        exercises: [exercise(name: 'Bench Press'), exercise(name: 'Row')]);
    expect(find.text('LOG 3 SETS ✓'), findsOneWidget);
    expect(interactiveCheckTiles, findsNothing);

    await tester.runAsync(() =>
        HiveService.instance.configBox.put(LogExerciseFlags.key, false));
    h.notifier.setElapsedSeconds(1); // any rebuild re-reads the flag
    await tester.pump();
    expect(find.textContaining('LOG 3 SETS'), findsNothing);
    expect(interactiveCheckTiles, findsWidgets);
    await unmountScreen(tester);
  });

  testWidgets('S1: one exercise logged, one not: FINISH names the skipped one',
      (tester) async {
    final h = await pumpScreen(tester,
        exercises: [exercise(name: 'Bench Press'), exercise(name: 'Row')]);
    await tapWithRealIo(tester, find.text('LOG 3 SETS ✓'));
    expect(h.state.isExerciseDone(0), isTrue);
    await openFinish(tester);
    expect(find.text('3/6 sets logged'), findsOneWidget);
    expect(
        find.text(WardroomCopy.activeFinishSkippedTemplate
            .replaceAll('{names}', 'Row')),
        findsOneWidget);
    await unmountScreen(tester);
  });

  testWidgets('S1: the header counts working sets; all warm-up reads 0%, no '
      'throw', (tester) async {
    await pumpScreen(tester,
        exercises: [exercise(name: 'Bench Press', sets: '2')],
        seed: (b) => b.copyWith(warmUpSets: const {'0-0': true, '0-1': true}));
    expect(tester.takeException(), isNull);
    expect(find.text('0%'), findsOneWidget);
    expect(find.textContaining('0 / 0 SETS'), findsOneWidget);
    await unmountScreen(tester);
  });

  testWidgets('SM2: RE-OPEN announces "<name> re-opened"', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpScreen(tester,
        exercises: [exercise(name: 'Bench Press'), exercise(name: 'Row')]);
    await tapWithRealIo(tester, find.text('LOG 3 SETS ✓'));
    // Past the re-open guard (kReopenGuard after an advancing LOG).
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 1300)));
    tester.takeAnnouncements();
    // The logged card collapsed when focus moved on; its DONE chip expands it.
    await tester.tap(find.text('✓ DONE'));
    await tester.pumpAndSettle();
    final logged = find.text('LOGGED ✓');
    await tester.ensureVisible(logged);
    await tester.pumpAndSettle();
    await tester.tap(logged);
    await tester.pumpAndSettle();
    final said = [for (final a in tester.takeAnnouncements()) a.message];
    expect(
        said,
        contains(WardroomCopy.activeReopenedAnnouncementTemplate
            .replaceAll('{exercise}', 'Bench Press')));
    handle.dispose();
    await unmountScreen(tester);
  });

  // Presence only (stated in the plan): the behaviour is SM2 above and the
  // controller tests (log_exercise_flip_behavioral_test.dart).
  group('source pins', () {
    String strip(String path) => stripDartComments(File(path).readAsStringSync());

    test('D1: the dev panel reads KILLED for a stored false (toast + row)', () {
      final src = strip('lib/features/dev/dev_panel_screen.dart');
      final toggle = functionBody(src, 'Future<void> _toggleLogExerciseButton()');
      expect(toggle.contains("next ? 'ON' : 'KILLED'"), isTrue);
      expect(
          src.contains(
              "LogExerciseFlags.logExerciseButtonEnabled ? 'ON' : 'KILLED'"),
          isTrue);
    });

    test('S2: RE-OPEN clears only its own UNDO toast and focuses the card',
        () {
      final src = strip('lib/features/train/screens/active_workout/screen.dart');
      final body = functionBody(src, 'void _onReopenExercise(int exIdx)');
      expect(body.contains('if (_logUndo?.exerciseIndex == exIdx) _clearLogUndo();'),
          isTrue);
      expect(body.contains('_focusExercise(exIdx);'), isTrue);
      expect(body.indexOf('if (outcome.kind != LogOutcomeKind.reopened) return;'),
          lessThan(body.indexOf('_focusExercise(exIdx);')));
    });
  });
}
