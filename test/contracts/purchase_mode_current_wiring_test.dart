// Plan section 7 test 1b (presence only): `PurchaseMode.current` is the one
// place the real build constants are read. A pure-resolver test cannot see
// that wiring: `flutter test` always has `dart.vm.product` false, so a
// hard-coded `isRelease: false` would leave every behavioural test green while
// shipping a purchase button in a store build.
//
// Source pins, comment-stripped. The behavioural proof of the real binary is
// the Profile footer line (`BuildStamp`) on the device.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _stripComments(String src) => src
    .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
    .split('\n')
    .map((l) => l.replaceFirst(RegExp(r'//.*$'), ''))
    .join('\n');

void main() {
  final src = _stripComments(
      File('lib/core/constants/purchase_mode.dart').readAsStringSync());

  // The body of `static PurchaseMode get current => ...;`
  final start = src.indexOf('static PurchaseMode get current');
  final end = src.indexOf(';', src.indexOf('raw:', start));
  final current = start < 0 || end < 0 ? '' : src.substring(start, end + 1);

  test('current is found', () => expect(current, isNotEmpty));

  test('current passes the three real build constants by name, each CONST', () {
    // Each argument is anchored to its separator, so `... && false` or
    // `kIsWeb || true` cannot satisfy the pin (B-pass F6).
    expect(RegExp(r'isWeb:\s*kIsWeb\s*,').hasMatch(current), isTrue);
    expect(
        RegExp(r"isRelease:\s*const\s+bool\.fromEnvironment\('dart\.vm\.product'\)\s*,")
            .hasMatch(current),
        isTrue,
        reason: 'the release flag must be a CONST read: an AOT build has no '
            'run-time environment, so a non-const read is always false there');
    expect(
        RegExp(r"raw:\s*const\s+String\.fromEnvironment\('ANDROID_PURCHASE_MODE'\)\s*,")
            .hasMatch(current),
        isTrue,
        reason: 'the define must be a CONST read (see above)');
  });

  test('no fromEnvironment read in this file is non-const', () {
    final reads = RegExp(r'(?<!const\s)(bool|String|int)\.fromEnvironment')
        .allMatches(src)
        .length;
    expect(reads, 0);
  });

  test('current reads no platform (CI runs on Linux)', () {
    expect(src.contains('dart:io'), isFalse);
    expect(src.contains('Platform.'), isFalse);
    expect(src.contains('defaultTargetPlatform'), isFalse);
  });

  test('the override is the only way to a non-resolved value', () {
    expect(current, contains('debugOverrideForTests ??'));
  });
}
