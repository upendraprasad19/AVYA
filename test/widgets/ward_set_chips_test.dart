// APK Test #12 / Theme E — pins the per-logging-type chip text format
// for the shared `WardSetChips` primitive. Receipt + Train expanded
// view both render through this widget, so a regression in chip text
// formatting would propagate to multiple surfaces.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/shared/widgets/wardroom/ward_set_chips.dart';

Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
}

void main() {
  group('WardSetChips chip-text format (Theme E)', () {
    testWidgets('weight_reps: "20 kg × 10 reps"', (tester) async {
      await _pump(
        tester,
        const WardSetChips(
          loggingType: 'weight_reps',
          perSetBreakdown: [
            WardSetChip(weightKg: 20, reps: 10),
          ],
        ),
      );
      expect(find.text('20 kg × 10 reps'), findsOneWidget);
    });

    testWidgets('bodyweight_reps: "× 10 reps"', (tester) async {
      await _pump(
        tester,
        const WardSetChips(
          loggingType: 'bodyweight_reps',
          perSetBreakdown: [
            WardSetChip(reps: 10),
          ],
        ),
      );
      expect(find.text('× 10 reps'), findsOneWidget);
    });

    testWidgets('weighted_bodyweight: "+10 kg × 8 reps"', (tester) async {
      await _pump(
        tester,
        const WardSetChips(
          loggingType: 'weighted_bodyweight',
          perSetBreakdown: [
            WardSetChip(weightKg: 10, reps: 8),
          ],
        ),
      );
      expect(find.text('+10 kg × 8 reps'), findsOneWidget);
    });

    testWidgets('timed: "60 secs"', (tester) async {
      await _pump(
        tester,
        const WardSetChips(
          loggingType: 'timed',
          perSetBreakdown: [
            WardSetChip(durationSeconds: 60),
          ],
        ),
      );
      expect(find.text('60 secs'), findsOneWidget);
    });

    testWidgets('cardio: "15s · 2.0 km"', (tester) async {
      await _pump(
        tester,
        const WardSetChips(
          loggingType: 'cardio',
          perSetBreakdown: [
            WardSetChip(durationSeconds: 15, distanceKm: 2.0),
          ],
        ),
      );
      expect(find.text('15s · 2.0 km'), findsOneWidget);
    });

    testWidgets('multiple sets render multiple chips', (tester) async {
      await _pump(
        tester,
        const WardSetChips(
          loggingType: 'weight_reps',
          perSetBreakdown: [
            WardSetChip(weightKg: 20, reps: 10),
            WardSetChip(weightKg: 20, reps: 10),
            WardSetChip(weightKg: 20, reps: 10),
          ],
        ),
      );
      expect(find.text('20 kg × 10 reps'), findsNWidgets(3));
    });

    testWidgets('empty perSetBreakdown + fallbackLabel renders one chip',
        (tester) async {
      await _pump(
        tester,
        const WardSetChips(
          loggingType: 'weight_reps',
          perSetBreakdown: [],
          fallbackLabel: '4 sets · 33 reps · 110 kg',
        ),
      );
      expect(find.text('4 sets · 33 reps · 110 kg'), findsOneWidget);
    });

    testWidgets('empty + no fallback → SizedBox.shrink', (tester) async {
      await _pump(
        tester,
        const WardSetChips(
          loggingType: 'weight_reps',
          perSetBreakdown: [],
        ),
      );
      // No chip text rendered — find should turn up nothing for the chip
      // text but the widget itself remains in the tree as SizedBox.
      expect(find.byType(WardSetChips), findsOneWidget);
      expect(find.byType(Text), findsNothing);
    });
  });
}
