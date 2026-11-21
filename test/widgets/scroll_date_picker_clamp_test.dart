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
    expect(
      seen.last,
      DateTime(2013, 10, 1),
      reason: 'the month is pulled back to October and the day (1) is kept',
    );
    // What the user SEES must agree with what was reported: the month wheel is
    // put back on October (item 9), not left on December.
    expect(_selected(tester, wheels.at(1)), 9);
    expect(_selected(tester, wheels.at(0)), 0, reason: 'day 1 untouched');
  });

  testWidgets('scrolling the day wheel past lastDate clamps the day',
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
                initialDate: last,
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

    await tester.drag(
      find.byType(ListWheelScrollView).first,
      const Offset(0, -76),
    );
    await tester.pumpAndSettle();

    expect(seen, isNotEmpty);
    for (final d in seen) {
      expect(d.isAfter(last), isFalse, reason: '$d is later than $last');
    }
    expect(seen.last, last, reason: 'the day stays on the last allowed day');
    expect(_selected(tester, find.byType(ListWheelScrollView).at(0)), 15,
        reason: 'the day wheel is put back on the 16th');
  });

  testWidgets('a seeded initialDate later than lastDate opens on lastDate',
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
                initialDate: DateTime(2015, 6, 1),
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

    final wheels = find.byType(ListWheelScrollView);
    expect(_selected(tester, wheels.at(0)), 15, reason: 'day 16');
    expect(_selected(tester, wheels.at(1)), 9, reason: 'October');
    expect(_selected(tester, wheels.at(2)), 2013 - 1940, reason: 'year 2013');
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

    // Two items BACK on the month wheel (a drag of 76 is safely past the touch
    // slop) lands before October: allowed, never clamped.
    await tester.drag(find.byType(ListWheelScrollView).at(1), const Offset(0, 76));
    await tester.pumpAndSettle();

    expect(seen, isNotEmpty, reason: 'the drag must have moved the wheel');
    expect(seen.last.isBefore(last), isTrue);
    expect(seen.last.year, 2013);
    expect(seen.last.month, lessThan(10));
    expect(seen.last.day, 1, reason: 'the day is untouched');
  });
}

int _selected(WidgetTester tester, Finder wheel) {
  final w = tester.widget<ListWheelScrollView>(wheel);
  return (w.controller! as FixedExtentScrollController).selectedItem;
}
