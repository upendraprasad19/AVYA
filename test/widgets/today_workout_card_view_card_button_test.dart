// Bug: on a squeezed left-column width (Obs 3, APK internal-testing batch
// 2026-09-14, founder-reported screenshot), the completed-state "VIEW CARD →"
// OutlinedButton had no overflow handling. The Text wrapped inside the
// StadiumBorder pill, deforming it into a tall, misshapen shape instead of a
// clean single-line pill.
//
// closes-diagnose: 2026-09-14-view-card-button-text-wrap-e2a917
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/features/home/widgets/today_workout_card.dart';

void main() {
  testWidgets(
    'completed-state VIEW CARD button renders on one line at a squeezed width',
    (tester) async {
      // 350px mirrors the card's real on-screen width (full-width card with
      // page padding, e.g. the founder's screenshot); the widget itself does
      // the 50/50 hero/macro split internally, so this width reproduces the
      // squeeze on the VIEW CARD button without the card's own required
      // content overflowing.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              child: TodayWorkoutCard(
                workoutName: 'PUSH A',
                onStart: () {},
                isDone: true,
                onViewCard: () {},
                bestLift: '60kg vol',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // No RenderFlex/overflow error thrown during layout.
      expect(tester.takeException(), isNull);

      final textWidget = tester.widget<Text>(find.text('VIEW CARD →'));
      expect(textWidget.maxLines, 1,
          reason: 'VIEW CARD text must be capped to one line, not wrap '
              'inside the stadium pill');
      expect(textWidget.softWrap, isFalse);
      expect(textWidget.overflow, TextOverflow.ellipsis);

      // The rendered text box must stay single-line height, not wrap taller.
      final renderBox = tester.renderObject<RenderBox>(
        find.text('VIEW CARD →'),
      );
      final singleLineHeight = textWidget.style!.fontSize! * 1.5;
      expect(renderBox.size.height, lessThanOrEqualTo(singleLineHeight));
    },
  );
}
