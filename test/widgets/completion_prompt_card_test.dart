// test/widgets/completion_prompt_card_test.dart
//
// Unit 1 (coach-completion-tap-card) — widget-level proof for the coach's
// early-finish prompt tile.
//
//   finding-3 — LAYOUT: two Expanded WardButtons ('LOG MORE' + the primary
//     CTA, both rendered UPPERCASE 11px Fraunces + 2.5 letter-spacing by
//     WardButton, whose inner Text neither wraps nor ellipsizes) must NOT trip
//     a RenderFlex horizontal overflow on a 375px device. The primary label was
//     shortened from 'Complete workout' → 'Complete' to fit both buttons in the
//     Row at the narrowest width.
//
//   finding-5 — CARD STATES: isBusy → both WardButtons disabled (onPressed
//     null) + a spinner present; planned == 0 → the "X of Y" progress line is
//     absent (an ad-hoc / plan-less day doesn't read "0 of 0"); planned > 0 →
//     the progress line shows "logged of planned".
//
// Real widget-pump tests (not source-grep). WardButton uses AppTypography
// (GoogleFonts) which degrades to a fallback font in the test env, so the pumps
// render without network.
//
// Run: flutter test test/widgets/completion_prompt_card_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:icanbefitter/features/ai_coach/widgets/completion_prompt_card.dart';
import 'package:icanbefitter/shared/widgets/wardroom/ward_button.dart';

/// Pumps [card] inside a [width]-wide surface so MediaQuery-derived layout
/// (the card's maxWidth = 88% of screen width) and the two-button Row are
/// measured at a realistic narrow-device width.
Future<void> _pumpAtWidth(
  WidgetTester tester,
  Widget card, {
  double width = 375,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: MediaQuery(
            data: MediaQueryData(size: Size(width, 812)),
            child: SizedBox(width: width, child: card),
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('CompletionPromptCard — finding-3 no overflow at 375px', () {
    testWidgets('two-button row does not RenderFlex-overflow at 375px width',
        (tester) async {
      await _pumpAtWidth(
        tester,
        CompletionPromptCard(
          planned: 5,
          logged: 2,
          onComplete: () {},
          onLogMore: () {},
        ),
      );

      // A RenderFlex overflow surfaces as an exception captured by the binding.
      expect(tester.takeException(), isNull,
          reason: 'The [Log more] · [Complete] button row must fit within a '
              '375px device — no RenderFlex horizontal overflow.');

      // Both buttons render.
      expect(find.byType(WardButton), findsNWidgets(2));
      // Primary CTA is the shortened 'Complete' (uppercased by WardButton).
      expect(find.text('COMPLETE'), findsOneWidget);
      expect(find.text('LOG MORE'), findsOneWidget);
    });

    testWidgets('no overflow at 375px while busy (spinner in the primary slot)',
        (tester) async {
      await _pumpAtWidth(
        tester,
        CompletionPromptCard(
          planned: 5,
          logged: 2,
          isBusy: true,
          onComplete: () {},
          onLogMore: () {},
        ),
      );
      expect(tester.takeException(), isNull,
          reason: 'The busy state (label + trailing spinner) must also fit '
              'within 375px.');
    });

    testWidgets('no overflow at a WIDE width (side-by-side Row branch)',
        (tester) async {
      // A tablet-width surface exercises the side-by-side Row branch of the
      // LayoutBuilder (the 375px cases fall to the stacked Column branch).
      await _pumpAtWidth(
        tester,
        CompletionPromptCard(
          planned: 5,
          logged: 2,
          isBusy: true,
          onComplete: () {},
          onLogMore: () {},
        ),
        width: 600,
      );
      expect(tester.takeException(), isNull,
          reason: 'Both buttons must sit side-by-side without overflow on a '
              'wide surface, even while busy.');
      expect(find.byType(WardButton), findsNWidgets(2));
    });
  });

  group('CompletionPromptCard — finding-5 card states', () {
    testWidgets('isBusy true → both WardButtons disabled + spinner present',
        (tester) async {
      await _pumpAtWidth(
        tester,
        CompletionPromptCard(
          planned: 3,
          logged: 1,
          isBusy: true,
          onComplete: () {},
          onLogMore: () {},
        ),
      );

      final buttons =
          tester.widgetList<WardButton>(find.byType(WardButton)).toList();
      expect(buttons.length, 2);
      for (final b in buttons) {
        expect(b.onPressed, isNull,
            reason: 'While busy, BOTH buttons must be disabled (onPressed null) '
                'so a double-tap cannot fire two completions.');
      }

      expect(find.byType(CircularProgressIndicator), findsOneWidget,
          reason: 'The busy state must show a spinner in the primary button.');
    });

    testWidgets('isBusy false → both WardButtons enabled + no spinner',
        (tester) async {
      await _pumpAtWidth(
        tester,
        CompletionPromptCard(
          planned: 3,
          logged: 1,
          onComplete: () {},
          onLogMore: () {},
        ),
      );

      final buttons =
          tester.widgetList<WardButton>(find.byType(WardButton)).toList();
      expect(buttons.length, 2);
      for (final b in buttons) {
        expect(b.onPressed, isNotNull,
            reason: 'When not busy, both buttons must be tappable.');
      }
      expect(find.byType(CircularProgressIndicator), findsNothing,
          reason: 'No spinner when not busy.');
    });

    testWidgets('planned == 0 → progress line absent', (tester) async {
      await _pumpAtWidth(
        tester,
        CompletionPromptCard(
          planned: 0,
          logged: 0,
          onComplete: () {},
          onLogMore: () {},
        ),
      );
      // The progress text is only shown when planned > 0, so an ad-hoc /
      // plan-less day never reads "0 of 0 logged so far.".
      expect(find.textContaining('logged so far'), findsNothing,
          reason: 'planned == 0 must suppress the "X of Y" progress line.');
    });

    testWidgets('planned > 0 → shows "X of Y" progress text', (tester) async {
      await _pumpAtWidth(
        tester,
        CompletionPromptCard(
          planned: 5,
          logged: 3,
          onComplete: () {},
          onLogMore: () {},
        ),
      );
      expect(find.text('3 of 5 logged so far.'), findsOneWidget,
          reason: 'planned > 0 must render the "logged of planned" progress '
              'line.');
    });
  });
}
