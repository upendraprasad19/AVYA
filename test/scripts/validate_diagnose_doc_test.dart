// test/scripts/validate_diagnose_doc_test.dart
//
// Tests for the diagnose-doc validator.
//
// Imports the library directly (no subprocess) so the suite runs under both
// `dart test` and `flutter test` without PATH or process-spawning issues.

import 'dart:io';
import 'package:test/test.dart';

// Import directly from the scripts/ directory.
import '../../scripts/validate_diagnose_doc_lib.dart';

/// Load a fixture file relative to the project root and validate it.
ValidationResult _validate(String fixturePath) {
  final root = Directory.current.path;
  final content = File('$root/$fixturePath').readAsStringSync();
  return validateDiagnoseDoc(content, projectRoot: root);
}

void main() {
  group('validate_diagnose_doc', () {
    test('exits 0 on valid sample', () {
      final result = _validate('test/scripts/fixtures/valid_diagnose.md');
      expect(result.isValid, isTrue,
          reason: 'Expected valid; got error: ${result.error}');
    });

    test('exits non-zero on missing field', () {
      final result =
          _validate('test/scripts/fixtures/missing_field_diagnose.md');
      expect(result.isValid, isFalse);
      expect(result.error, contains('missing required field'));
    });

    test('exits non-zero on placeholder value (TBD)', () {
      final result =
          _validate('test/scripts/fixtures/placeholder_diagnose.md');
      expect(result.isValid, isFalse);
      expect(result.error, contains('placeholder value'));
    });

    test('exits non-zero on file:line not resolving', () {
      final result =
          _validate('test/scripts/fixtures/bad_fileline_diagnose.md');
      expect(result.isValid, isFalse);
      expect(result.error, contains('does not resolve'));
    });
  });
}
