import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late String welcomeSrc;

  setUpAll(() {
    welcomeSrc = File('lib/features/onboarding/screens/welcome_screen.dart')
        .readAsStringSync();
  });

  test('BEGIN ENLISTMENT must route to mission-brief, not identity', () {
    expect(
      welcomeSrc.contains("go('/onboarding/identity')"),
      isFalse,
      reason: 'Direct jump to identity skips RestoringScreen and Mission Brief',
    );
    expect(
      welcomeSrc.contains("go('/onboarding/mission-brief')"),
      isTrue,
      reason: 'New users must see the Mission Brief before Identity step',
    );
  });
}
