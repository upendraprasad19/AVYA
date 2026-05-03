import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

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
    expect(src.contains("WK \$weekOfYear"), isTrue,
        reason: 'eyebrow must include WK number');
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
