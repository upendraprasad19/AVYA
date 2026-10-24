// ⑧ 8-B / UNIT 3-b — the graduation "repeat vs advance" choice: the pure gate,
// the sheet widget, and the _onPro wiring. `_onPro` is private on a private
// ConsumerState (unreachable in a test) so its logic is pinned SOURCE-anchored
// (comment-stripped); the pure gate + the sheet are behaviorally tested.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:icanbefitter/features/train/widgets/advance_choice_sheet.dart';

String _strip(String s) {
  final noBlock = s.replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '');
  return noBlock
      .split('\n')
      .map((l) {
        final i = l.indexOf('//');
        return i >= 0 ? l.substring(0, i) : l;
      })
      .join('\n');
}

void main() {
  group('shouldOfferAdvanceChoice (pure gate)', () {
    test('low completion (< threshold) → offer the choice', () {
      expect(shouldOfferAdvanceChoice(completionRate: 0.5, threshold: 0.8),
          isTrue);
      expect(shouldOfferAdvanceChoice(completionRate: 0.0, threshold: 0.8),
          isTrue);
    });
    test('at/above threshold → do NOT offer (advance fresh silently)', () {
      expect(shouldOfferAdvanceChoice(completionRate: 0.8, threshold: 0.8),
          isFalse);
      expect(shouldOfferAdvanceChoice(completionRate: 0.95, threshold: 0.8),
          isFalse);
    });
  });

  group('showAdvanceChoiceSheet (widget)', () {
    Future<AdvanceChoice?> openThen(
        WidgetTester tester, Future<void> Function() act) async {
      AdvanceChoice? result;
      var done = false;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(builder: (ctx) {
            return Center(
              child: ElevatedButton(
                onPressed: () async {
                  result = await showAdvanceChoiceSheet(ctx);
                  done = true;
                },
                child: const Text('open'),
              ),
            );
          }),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await act();
      await tester.pumpAndSettle();
      expect(done, isTrue, reason: 'the sheet future must complete');
      return result;
    }

    testWidgets('renders both forward options (non-shaming)', (tester) async {
      final r = await openThen(tester, () async {
        // assert both options are present before dismissing
        expect(find.text('RUN THE SAME DRILLS AGAIN'), findsOneWidget);
        expect(find.text('GIVE ME FRESH ORDERS'), findsOneWidget);
        // W3.1 (Batch 10): the non-shaming "why" lead-in — explains the trigger
        // (an unfinished block) with NO completion %.
        expect(find.textContaining('open sets'), findsOneWidget);
        await tester.tapAt(const Offset(10, 10)); // dismiss via barrier
      });
      expect(r, isNull);
    });

    testWidgets('tapping "repeat" returns AdvanceChoice.repeat', (tester) async {
      final r = await openThen(tester,
          () => tester.tap(find.text('RUN THE SAME DRILLS AGAIN')));
      expect(r, AdvanceChoice.repeat);
    });

    testWidgets('tapping "fresh orders" returns AdvanceChoice.advance',
        (tester) async {
      final r = await openThen(
          tester, () => tester.tap(find.text('GIVE ME FRESH ORDERS')));
      expect(r, AdvanceChoice.advance);
    });

    testWidgets('barrier dismiss returns null (caller advances fresh)',
        (tester) async {
      final r =
          await openThen(tester, () => tester.tapAt(const Offset(10, 10)));
      expect(r, isNull);
    });
  });

  group('graduation _onPro wiring (source-anchored)', () {
    final src = _strip(
        File('lib/features/train/screens/graduation_screen.dart')
            .readAsStringSync());

    test('the choice is FLAG-short-circuited (no eager rate eval when OFF)', () {
      expect(
          RegExp(r'PlanEngineFlags\.adherenceGateEnabled\s*&&\s*shouldOfferAdvanceChoice')
              .hasMatch(src),
          isTrue,
          reason: 'the ~90-Hive-read currentPhaseCompletionRate must never run '
              'when the flag is OFF (byte-identical inertness)');
    });
    test('abort-if-changed guards a concurrent advance (never a phase SKIP)',
        () {
      expect(
          RegExp(r"if \(live >= nextPhase\)[\s\S]{0,300}?context\.go\('/train'\)")
              .hasMatch(src),
          isTrue,
          reason: 'a concurrent advance while the sheet is open must ROUTE to '
              '/train, not recompute nextPhase (that skips a phase)');
    });
    // Unit B / OI-84 (2026-08-03): the two assertions below used to match a
    // single regex inside graduation_screen._onPro. The hoist SPLIT that chain
    // across two files — the screen decides `repeat`, the shared advance turns
    // it into pins — so each half is now pinned where it actually lives, plus
    // the seam between them. Keeping the old single-file regex would have left
    // both silently unmatched.
    final advanceSrc = _strip(
        File('lib/shared/services/pro_phase_advance.dart').readAsStringSync());

    test('the screen passes the repeat CHOICE to the shared advance', () {
      expect(
          RegExp(r'repeat:\s*choice == AdvanceChoice\.repeat').hasMatch(src),
          isTrue,
          reason: 'the AdvanceChoice enum stays in the feature layer; the '
              'shared advance takes a plain bool. NB: lib/shared -> lib/features '
              'is a CONVENTION, not a gated rule (four imports already breach '
              'it) — this pins the chosen design, it does not claim an '
              'invariant');
    });
    test('pins built ONLY on an explicit repeat choice', () {
      expect(
          RegExp(r'final pins = repeat[\s\S]{0,120}?buildRepeatPinsForAdvance')
              .hasMatch(advanceSrc),
          isTrue);
    });
    test('the repeat nudge is flagged on pins != null (the actual repeat)', () {
      // `pins != null`, NOT the user's `repeat` choice —
      // buildRepeatPinsForAdvance returns null when its G5 frame-shape gate
      // rejects, and the nudge must follow what actually happened.
      expect(
          RegExp(r'repeatNudgeFlagged = pins != null[\s\S]{0,200}?markPhaseRepeatNudgePending')
              .hasMatch(advanceSrc),
          isTrue);
    });
    test('the nudge PROVIDER invalidation stays in the widget layer', () {
      // The Hive write moved to shared/; the provider invalidate could not,
      // because phaseRepeatNudgeProvider lives in lib/features/home/. The
      // result flag is the seam — if it were dropped, the nudge would still be
      // written but would not surface until an app relaunch.
      expect(
          RegExp(r'result\.repeatNudgeFlagged[\s\S]{0,120}?invalidate\(phaseRepeatNudgeProvider\)')
              .hasMatch(src),
          isTrue);
      expect(advanceSrc.contains('phaseRepeatNudgeProvider'), isFalse,
          reason: 'the shared advance must not reach into this lib/features '
              'provider — it returns repeatNudgeFlagged and the widget '
              'invalidates. (A convention, not a gated invariant: four '
              'lib/shared -> lib/features imports already exist. This pins the '
              'seam this unit chose, not a repo-wide law.)');
    });
  });
}
