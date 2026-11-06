// scripts/validate_agent_diagnose_stanza.dart
//
// Validates that a raw agent text output contains a well-formed diagnose_stanza.
// Usage: dart run scripts/validate_agent_diagnose_stanza.dart <path>
//
// Exit codes:
//   0  — valid stanza found
//   1  — validation failure (details on stderr)
//   2  — usage error (no path given, file not found)

import 'dart:io';
import 'validate_agent_diagnose_stanza_lib.dart';

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln(
        'Usage: dart run scripts/validate_agent_diagnose_stanza.dart <path>');
    exit(2);
  }
  final file = File(args[0]);
  if (!file.existsSync()) {
    stderr.writeln('File not found: ${args[0]}');
    exit(2);
  }
  final result = validateAgentDiagnoseStanza(file.readAsStringSync());
  if (!result.isValid) {
    stderr.writeln(result.error);
    exit(1);
  }
  stdout.writeln('OK: stanza valid');
  exit(0);
}
