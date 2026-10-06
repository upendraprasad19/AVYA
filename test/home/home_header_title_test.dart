import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late String src;

  setUpAll(() {
    src = File('lib/features/home/screens/home_screen.dart').readAsStringSync();
  });

  test('home header title must not embed firstName after greeting', () {
    // Source file used to contain: title: '$greeting, $firstName.'
    // The original Test #7 fix (and this guard) prevented the double-name
    // bug. Test #10 obs 1 keeps that invariant: the greeting eyebrow now
    // comes from userTimeOfDayProvider (mono caps WITHOUT the name suffix);
    // the firstName is rendered on a separate row below the eyebrow.
    expect(
      src.contains("greeting, \$firstName"),
      isFalse,
      reason: 'greeting already contains the name — doubling it wraps to 3 lines',
    );
  });

  test('home header uses userTimeOfDayProvider eyebrow + firstName body', () {
    // Test #10 obs 1 — header redesign decoupled the greeting from the
    // name. Eyebrow line is `userTimeOfDayProvider` (e.g. "GOOD EVENING,"
    // mono caps); the name line below uses `userFirstNameProvider`. The
    // legacy `'$greeting.'` Text widget is gone — that contract is now
    // covered by the two halves of this stack.
    expect(
      src.contains('userTimeOfDayProvider'),
      isTrue,
      reason: 'header should source the new mono-caps time-of-day eyebrow',
    );
    expect(
      src.contains('userFirstNameProvider'),
      isTrue,
      reason: 'header should render the user first name from the existing provider',
    );
    expect(
      src.contains("'\$timeOfDay,'"),
      isTrue,
      reason: 'eyebrow uses `\$timeOfDay,` (with trailing comma) — pin the format',
    );
    // The legacy single-line `'$greeting.'` Text is no longer rendered in
    // the header. If a future refactor reintroduces it without removing
    // the new stack, this assertion fires as a regression signal.
    expect(
      src.contains("'\$greeting.'"),
      isFalse,
      reason: 'legacy single-line greeting Text was removed by Test #10 obs 1',
    );
  });
}
