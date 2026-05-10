// scripts/validate_diagnose_doc.dart
//
// Validates a diagnose-doc's YAML frontmatter.
// Usage: dart run scripts/validate_diagnose_doc.dart <path>
//
// Exit codes:
//   0  — valid
//   1  — validation failure (details on stderr)
//   2  — usage error (no file, file not found)

import 'dart:io';
import 'validate_diagnose_doc_lib.dart';

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('Usage: dart run scripts/validate_diagnose_doc.dart <path>');
    exit(2);
  }
  final path = args[0];
  final file = File(path);
  if (!file.existsSync()) {
    stderr.writeln('File not found: $path');
    exit(2);
  }

  final content = file.readAsStringSync();
  final result = validateDiagnoseDoc(content);
  if (result.isValid) {
    stdout.writeln('OK: $path passes diagnose-doc validation');
    exit(0);
  } else {
    stderr.writeln(result.error!);
    exit(1);
  }
}
