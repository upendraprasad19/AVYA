// The readiness sheet has TWO states and this pins which one it picks.
//
//   STATE A -- a sleep measurement exists  -> show it, 2 tap rows.
//   STATE B -- none                        -> ask for sleep, 3 tap rows.
//
// Why the decision lives in a pure function rather than the widget: a private
// `initState` branch cannot be mutation-tested, and building the sheet in a
// `testWidgets` body walks straight into the GoogleFonts/path_provider trap
// documented in CLAUDE.md 4.9 (this sheet renders AppTypography styles AND
// needs Hive open for HealthReadService -- that trap's exact recipe).
//
// So: the DECISION is tested behaviorally here, and the WIRING (that the sheet
// actually delegates to it rather than re-deriving the branch inline) is pinned
// by a source assertion -- the same split the repo already uses for
// effectiveLoadFactor in readiness_checkin_behavioral_test.dart.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/utils/readiness.dart';

void main() {
  group('resolveSleepAxis — which state the sheet picks', () {
    test('no measurement → null → STATE B, the sheet must ASK', () {
      expect(resolveSleepAxis(null), isNull);
    });

    test('measurement → the MAPPED axis → STATE A, no tap needed', () {
      expect(resolveSleepAxis(7.33), 0); // >6.5  Solid
      expect(resolveSleepAxis(5.0), 1); // mid    Okay
      expect(resolveSleepAxis(3.0), 2); // <4.5   Rough
    });

    test('boundaries stay in the middle band through the resolver', () {
      expect(resolveSleepAxis(6.5), 1);
      expect(resolveSleepAxis(4.5), 1);
    });

    test('a measured ROUGH night still only contributes ONE flag', () {
      // Guards against a future "measured sleep counts double" shortcut:
      // rough sleep alone must stay yellow, never red.
      final axis = resolveSleepAxis(3.0)!;
      expect(readinessLevelFor(sleep: axis, soreness: 0, energy: 0),
          ReadinessLevel.yellow);
    });
  });

  group('wiring — the sheet must DELEGATE, not re-derive', () {
    String stripComments(String src) => src
        .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '')
        .replaceAll(RegExp(r'//[^\n]*'), '');

    test('readiness_sheet calls resolveSleepAxis', () {
      final code = stripComments(
          File('lib/features/train/widgets/readiness_sheet.dart')
              .readAsStringSync());
      expect(code.contains('resolveSleepAxis('), isTrue,
          reason: 'the sheet must ask resolveSleepAxis which state it is in — '
              'an inline null-check here is invisible to every test above.');
    });

    test('the sync nudge is TAPPABLE — the only in-sheet grant path', () {
      final code = stripComments(
          File('lib/features/train/widgets/readiness_sheet.dart')
              .readAsStringSync());
      // Without this, requestSleepPermission has no caller and State A can
      // never be reached on a device that has not already granted sleep.
      expect(code.contains('requestSleepPermission('), isTrue,
          reason: 'State B nudge must request the Health Connect sleep grant');
      expect(code.contains('GestureDetector'), isTrue,
          reason: 'the nudge must be tappable, not a bare Text');
    });
  });
}
