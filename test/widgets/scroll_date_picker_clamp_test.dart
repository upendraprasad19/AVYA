// OI-305 (2026-10-16): the conversational onboarding date of birth uses
// ScrollDatePicker, whose year wheel stops at lastDate.year but whose month and
// day wheels used to reach later dates in that year (born 31 Dec of the last
// allowed year = younger than the floor). The picker now clamps to lastDate.
@Timeout(Duration(minutes: 2))
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/shared/widgets/scroll_date_picker.dart';

void main() {
  testWidgets('scrolling the month wheel past lastDate clamps to lastDate',
      (tester) async {
    final last = DateTime(2013, 10, 16);
    final seen = <DateTime>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 360,
              child: ScrollDatePicker(
                initialDate: DateTime(2013, 10, 1),
                firstDate: DateTime(1940),
                lastDate: last,
                onDateChanged: seen.add,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The month wheel is the middle one: two items forward is December.
    final wheels = find.byType(ListWheelScrollView);
    expect(wheels, findsNWidgets(3), reason: 'day, month, year wheels');
    await tester.drag(wheels.at(1), const Offset(0, -76));
    await tester.pumpAndSettle();

    expect(seen, isNotEmpty, reason: 'the wheel must have reported a change');
    for (final d in seen) {
      expect(d.isAfter(last), isFalse, reason: '$d is later than $last');
    }
    expect(seen.last, last, reason: 'the last report is the clamped date');
  });

  testWidgets('a date before lastDate in the same year is not clamped',
      (tester) async {
    final last = DateTime(2013, 10, 16);
    final seen = <DateTime>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 360,
              child: ScrollDatePicker(
                initialDate: DateTime(2013, 10, 1),
                firstDate: DateTime(1940),
                lastDate: last,
                onDateChanged: seen.add,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // One item BACK on the month wheel is September: allowed.
    await tester.drag(find.byType(ListWheelScrollView).at(1), const Offset(0, 38));
    await tester.pumpAndSettle();

    expect(seen, isNotEmpty);
    expect(seen.last, DateTime(2013, 9, 1));
  });
}
