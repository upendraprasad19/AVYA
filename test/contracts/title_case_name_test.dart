// OBS-13 (2026-06-23) — titleCaseName contract. `completeOnboarding` routes
// full_name through this so a lowercase-typed web name ("test three") is stored
// canonical ("Test Three") instead of greeting the user "Recruit test".
// (`textCapitalization.words` is a mobile keyboard hint only — no effect on web.)
//
// Run: flutter test test/contracts/title_case_name_test.dart

import 'dart:io';

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

  // Hermes 2026-06-25 — OBS-13 has TWO persistence writers of full_name; the
  // first fix only covered onboarding. Pin that EVERY raw-input writer applies
  // titleCaseName, so a Profile edit (esp. on web, where the keyboard hint is
  // inert) cannot re-save un-title-cased casing.
  group('OBS-13 full_name writers — every persistence writer title-cases', () {
    test('onboarding completeOnboarding applies titleCaseName to full_name', () {
      final src = _stripDartComments(
          File('lib/features/onboarding/providers/onboarding_provider.dart')
              .readAsStringSync());
      expect(src.contains("'full_name': titleCaseName("), isTrue,
          reason: 'onboarding is the 1st full_name writer — must title-case.');
    });

    test('Edit Profile save applies titleCaseName to full_name (2nd writer)', () {
      final src = _stripDartComments(
          File('lib/features/profile/screens/edit_profile_screen.dart')
              .readAsStringSync());
      expect(src.contains("'full_name': titleCaseName("), isTrue,
          reason: 'OBS-13 incompleteness fix: the Edit Profile writer must '
              'title-case too, else a web edit re-saves raw lowercase casing.');
    });
  });
}

/// Strips `/* */` blocks then `// ...` line comments so the source-grep assertion
/// matches real CODE, not a comment. Per feedback_source_grep_strip_comments_first.
String _stripDartComments(String src) {
  final noBlock = src.replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '');
  return noBlock.split('\n').map((l) {
    final i = l.indexOf('//');
    return i >= 0 ? l.substring(0, i) : l;
  }).join('\n');
}
