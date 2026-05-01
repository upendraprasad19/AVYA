import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late String src;

  setUpAll(() {
    src = File('lib/features/ai_coach/screens/induction_screen.dart')
        .readAsStringSync();
  });

  test('pledge must reference Sub Lieutenant, not Lieutenant Commander', () {
    expect(src.contains('Lieutenant Commander rank'), isFalse,
        reason: 'Sub Lieutenant (W104) is the first officer commission');
    expect(src.contains('Sub Lieutenant rank'), isTrue);
  });

  test('pledge must reference 104 workouts, not 200', () {
    expect(src.contains('200 workouts'), isFalse);
    expect(src.contains('104 workouts'), isTrue);
  });

  test('pledge must reference six months, not twelve', () {
    expect(src.contains('twelve months'), isFalse);
    expect(src.contains('six months'), isTrue);
  });
}
