import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

String _strip(String s) => s
    .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '')
    .replaceAll(RegExp(r'//[^\n]*'), '');

/// Pins the heading-clip fix (diagnose b2e9d4): the four tab-screen headers
/// shrink-to-fit (FittedBox scaleDown) instead of truncating with ellipsis.
void main() {
  const files = <String>[
    'lib/features/train/screens/train/plan_header.dart',
    'lib/features/nutrition/screens/nutrition_screen.dart',
    'lib/features/home/screens/home_screen.dart',
    'lib/features/ai_coach/screens/ai_coach/compact_header.dart',
  ];

  group('tab headers shrink-to-fit (no clip)', () {
    for (final f in files) {
      test('$f wraps its title in FittedBox(scaleDown)', () {
        final s = _strip(File(f).readAsStringSync());
        expect(s.contains('BoxFit.scaleDown'), isTrue,
            reason: '$f title should shrink-to-fit, not ellipsize');
      });
    }
  });
}
