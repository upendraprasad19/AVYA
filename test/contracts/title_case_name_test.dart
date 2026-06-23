// OBS-13 (2026-06-23) — titleCaseName contract. `completeOnboarding` routes
// full_name through this so a lowercase-typed web name ("test three") is stored
// canonical ("Test Three") instead of greeting the user "Recruit test".
// (`textCapitalization.words` is a mobile keyboard hint only — no effect on web.)
//
// Run: flutter test test/contracts/title_case_name_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/utils/name_format.dart';

void main() {
  group('titleCaseName (OBS-13)', () {
    test('lowercase multi-word → title-cased (the live web bug)', () {
      expect(titleCaseName('test three'), 'Test Three');
    });
    test('collapses runs of whitespace + trims', () {
      expect(titleCaseName('  john   doe  '), 'John Doe');
    });
    test('preserves an already-capitalized interior (McDonald / O\'Brien)', () {
      expect(titleCaseName('ronald McDonald'), 'Ronald McDonald');
      expect(titleCaseName("conor o'Brien"), "Conor O'Brien");
    });
    test('single word', () {
      expect(titleCaseName('avya'), 'Avya');
    });
    test('empty / whitespace-only → empty (no crash)', () {
      expect(titleCaseName(''), '');
      expect(titleCaseName('   '), '');
    });
  });
}
