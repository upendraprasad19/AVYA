import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late String src;

  setUpAll(() {
    src = File('lib/shared/widgets/wardroom/ward_status_strip.dart')
        .readAsStringSync();
  });

  test('WardFreezeBadge must not appear in WardStatusStrip', () {
    expect(
      src.contains('WardFreezeBadge'),
      isFalse,
      reason: 'StreakBadge already renders the inline freeze count — '
          'a second WardFreezeBadge produces a duplicate display',
    );
  });

  test('StreakBadge receives the real freezesAvailable value', () {
    expect(
      src.contains('freezesAvailable: freezesAvailable'),
      isTrue,
      reason: 'hardcoded 0 hid the freeze count inside the streak pill',
    );
  });
}
