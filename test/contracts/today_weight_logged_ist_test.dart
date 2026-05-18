// Bug w7r4c3 adjacent fix — IST drift in TodayWeightLoggedNotifier.
//
// HealthWriteService.logWeight writes Hive key `weight_<istDateStr>`
// (lib/core/services/health_write_service.dart:122). Pre-fix, the
// reader TodayWeightLoggedNotifier in home_provider.dart computed
// `weight_<deviceLocalYYYY-MM-DD>` from raw DateTime.now() pieces.
// At IST 00:00-05:30 the device-local UTC date is the prior day,
// so a freshly-written today-IST weight returned `false` here and
// the "log weight" pill on Home stayed in its unlogged state until
// ~05:30 IST.
//
// Source-grep contract: TodayWeightLoggedNotifier must call
// istDateStr(DateTime.now()) and must NOT use the hand-rolled
// padded year/month/day formula.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
      'w7r4c3 — TodayWeightLoggedNotifier.build uses istDateStr, not device-local YYYY-MM-DD',
      () {
    final src =
        File('lib/features/home/providers/home_provider.dart')
            .readAsStringSync();

    // Locate the class. We want to constrain the assertion to its body.
    final classIdx = src.indexOf('class TodayWeightLoggedNotifier');
    expect(classIdx, isNonNegative,
        reason:
            'TodayWeightLoggedNotifier class moved or renamed — re-baseline this test.');

    // Slice ~30 lines after the class declaration to scope the check.
    final scoped = src.substring(classIdx, classIdx + 1200);

    // Strip comments inside the scoped block so we don't match the
    // explanatory comment that names the anti-pattern.
    final stripped = scoped
        .replaceAll(RegExp(r'/\*[\s\S]*?\*/', multiLine: true), '')
        .split('\n')
        .map((l) => l.replaceFirst(RegExp(r'//.*$'), ''))
        .join('\n');

    expect(
      stripped.contains('istDateStr(DateTime.now())'),
      isTrue,
      reason:
          'TodayWeightLoggedNotifier.build must use istDateStr(DateTime.now()) '
          'to match the writer key formula at health_write_service.dart:122.',
    );
    expect(
      stripped.contains(
          RegExp(r'\$\{[^}]*\.year\}.*\$\{[^}]*\.month\.toString')),
      isFalse,
      reason:
          'TodayWeightLoggedNotifier.build must not hand-roll YYYY-MM-DD from '
          'device-local DateTime parts. Use istDateStr from lib/core/utils/ist_date.dart.',
    );
  });
}
