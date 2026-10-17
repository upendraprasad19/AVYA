import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/utils/hold_week_labels.dart';

/// F8 · Test #9 — Home header layout invariants.
///
/// Source-grep style: asserts the home_screen.dart file maintains the
/// 3-row + 1-gold-rule header pattern locked in the spec. Catches the
/// next "let me add a status strip back below the divider" drift.
void main() {
  late String src;

  setUpAll(() {
    final f = File('lib/features/home/screens/home_screen.dart');
    expect(f.existsSync(), isTrue, reason: 'Run from project root');
    src = f.readAsStringSync();
  });

  test('eyebrow contains DAILY + date weekday + WK + PHASE meta', () {
    expect(src.contains("'DAILY · \${weekdays[now.weekday - 1]}"), isTrue,
        reason: 'eyebrow must include DAILY · weekday');
    // The literal used to be inlined here as `WK $weekInPhase`. FOB-1 / OI-60
    // moved it into the shared formatter, because a hold week has no honest
    // week number and the eyebrow must show `HOLDING · Hn` instead — so the
    // segment is now computed, not hardcoded. Assert BOTH halves: that the
    // eyebrow still sources a week segment, and that the segment really is
    // "WK n" for a non-holding user. The second half is a behavioural
    // assertion rather than a grep, which is what the original `reason` below
    // was actually trying to protect.
    expect(src.contains('homeWeekSegment('), isTrue,
        reason: 'eyebrow must include WK number (phase-relative week, '
            'renamed from weekOfYear — diagnose a7d3f1)');
    expect(homeWeekSegment(holdOrdinal: null, weekInPhase: 2), 'WK 2',
        reason: 'the non-holding eyebrow segment IS the WK number; see '
            'test/contracts/hold_week_labels_test.dart for both arms');
    expect(src.contains("PHASE \$currentPhase"), isTrue,
        reason: 'eyebrow must include PHASE number');
  });

  test('_buildDateDisplay() helper is removed (date hero dropped)', () {
    expect(src.contains('_buildDateDisplay'), isFalse,
        reason: 'F8 dropped the duplicate date hero. _buildDateDisplay should be deleted.');
  });

  test('Home header renders streak via WardStatusStrip in a Padding row', () {
    expect(src.contains('WardStatusStrip('), isTrue);
  });
}
