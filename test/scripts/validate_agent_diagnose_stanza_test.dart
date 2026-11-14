// test/scripts/validate_agent_diagnose_stanza_test.dart
//
// Tests for the agent diagnose-stanza validator.
//
// Imports the library directly (no subprocess) so the suite runs under both
// `dart test` and `flutter test` without PATH or process-spawning issues.

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

import '../../scripts/validate_agent_diagnose_stanza_lib.dart';

void main() {
  group('validate_agent_diagnose_stanza_lib', () {
    test('exits 0 when agent output has valid stanza', () {
      final content = File(
        '${Directory.current.path}/test/scripts/fixtures/agent_output_valid.txt',
      ).readAsStringSync();
      final result = validateAgentDiagnoseStanza(content);
      expect(result.isValid, isTrue, reason: 'error: ${result.error}');
    });

    test('exits non-zero when stanza missing', () {
      final content = File(
        '${Directory.current.path}/test/scripts/fixtures/agent_output_no_stanza.txt',
      ).readAsStringSync();
      final result = validateAgentDiagnoseStanza(content);
      expect(result.isValid, isFalse);
      expect(result.error, contains('no diagnose_stanza found'));
    });

    test('exits non-zero when stanza has placeholder', () {
      final content = File(
        '${Directory.current.path}/test/scripts/fixtures/agent_output_placeholder.txt',
      ).readAsStringSync();
      final result = validateAgentDiagnoseStanza(content);
      expect(result.isValid, isFalse);
      expect(result.error, contains('placeholder'));
    });
  });
}
