import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late String src;

  setUpAll(() {
    src = File('lib/features/home/screens/home_screen.dart').readAsStringSync();
  });

  test('home header title must not embed firstName after greeting', () {
    // Source file contains: title: '$greeting, $firstName.'
    // After fix it should NOT contain the double-name pattern.
    expect(
      src.contains("greeting, \$firstName"),
      isFalse,
      reason: 'greeting already contains the name — doubling it wraps to 3 lines',
    );
  });

  test('home header title ends with greeting + period only', () {
    // Source file should contain: title: '$greeting.',
    expect(
      src.contains("title: '\$greeting.'"),
      isTrue,
      reason: 'title should be the greeting sentence closed with a period',
    );
  });
}
