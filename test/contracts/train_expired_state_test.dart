// Regression contract for APK +34 / obs 1+6 (diagnose b6e1c3): the Train screen
// must gate on isPhaseExpired() and surface PlanExpiredCard (the recovery path),
// instead of always highlighting a "current" week + showing a hero/empty card
// past plan-end. Home already did this; Train had NO expired state, which is why
// it highlighted a bogus/last week as TODAY with "no workouts" while completed
// ticks showed on other weeks (a contradiction).
//
// The expiry DECISION semantic is pinned behaviorally by
// plan_expiry_respects_schedule_test.dart (isPhaseExpiredFrom). This guards the
// Train screen from regressing to never consuming it.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _strip(String src) {
  var s = src.replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '');
  s = s
      .split('\n')
      .map((line) {
        final m = RegExp(r'(?<!:)//').firstMatch(line);
        return m == null ? line : line.substring(0, m.start);
      })
      .join('\n');
  return s;
}

void main() {
  test('Train screen surfaces PlanExpiredCard when the phase is expired', () {
    final src = _strip(
        File('lib/features/train/screens/train/screen.dart').readAsStringSync());
    expect(src.contains('isPhaseExpired'), isTrue,
        reason: 'Train must gate the hero slot on isPhaseExpired, like Home');
    expect(src.contains('PlanExpiredCard'), isTrue,
        reason: 'Train must surface the recovery card when the phase expired');
  });
}
