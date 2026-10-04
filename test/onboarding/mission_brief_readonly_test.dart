import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late String src;

  setUpAll(() {
    src = File('lib/features/onboarding/screens/mission_brief_screen.dart')
        .readAsStringSync();
  });

  test('MissionBriefScreen declares readOnly parameter', () {
    expect(src.contains('readOnly'), isTrue,
        reason: 'readOnly param needed to suppress CONTINUE when opened from Profile');
  });

  test('CONTINUE button is conditional on readOnly being false', () {
    expect(src.contains('if (!readOnly)'), isTrue,
        reason: 'CONTINUE button must be hidden when readOnly = true');
  });

  test('AppBar is conditional on readOnly', () {
    expect(
      src.contains('appBar: readOnly'),
      isTrue,
      reason: 'back arrow AppBar must only appear in readOnly mode',
    );
  });
}
