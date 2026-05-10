// scripts/validate_diagnose_doc_lib.dart
//
// Pure validation logic — importable by tests without spawning a subprocess.
// The CLI entry point (validate_diagnose_doc.dart) delegates to this.

import 'dart:io';

const requiredFields = <String>[
  'bug_id', 'date', 'batch', 'status', 'symptom', 'concept',
  'sot_registry_entry', 'writers', 'readers', 'hive_key_prefix',
  'hive_key_formula', 'sync_methods', 'restore_methods', 'cloud_table',
  'cloud_columns', 'contract_test_path', 'ist_handling',
  'provider_invalidations', 'telemetry_op_types', 'cross_account_guard',
  'forbidden_patterns_checked', 'proposed_fix', 'regression_test_planned',
];

const placeholderPatterns = <String>[
  'TBD', 'TODO', '<...>', '???', 'tbd', 'todo',
];

/// Result of validating a diagnose-doc.
class ValidationResult {
  final bool isValid;
  final String? error;

  const ValidationResult.ok()
      : isValid = true,
        error = null;
  const ValidationResult.fail(this.error) : isValid = false;
}

/// Validate a diagnose-doc given its full [content] string.
///
/// The [projectRoot] parameter is used to resolve file:line references.
/// Defaults to the current working directory.
ValidationResult validateDiagnoseDoc(
  String content, {
  String? projectRoot,
}) {
  final root = projectRoot ?? Directory.current.path;

  // Normalize line endings (CRLF → LF) so the regex works on Windows.
  final normalised = content.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

  // Extract YAML frontmatter block between the first pair of `---` delimiters.
  final fmMatch =
      RegExp(r'^---\n(.*?)\n---', dotAll: true).firstMatch(normalised);
  if (fmMatch == null) {
    return const ValidationResult.fail('No YAML frontmatter found');
  }
  final fm = fmMatch.group(1)!;

  // 1. Required field presence
  for (final field in requiredFields) {
    if (!RegExp('^$field:', multiLine: true).hasMatch(fm)) {
      return ValidationResult.fail('missing required field: $field');
    }
  }

  // 2. Placeholder scan
  for (final placeholder in placeholderPatterns) {
    if (fm.contains(placeholder)) {
      return ValidationResult.fail(
          'placeholder value detected: $placeholder');
    }
  }

  // 3. file:line resolution for writers / readers / ist_handling entries.
  //
  // Matches YAML inline-map entries like:
  //   { file: lib/foo.dart, method: bar, line: 42 }
  //   { file: lib/foo.dart, line: 42, source: ... }
  final fileLineRegex = RegExp(
    r'\{[^}]*file:\s*([^\s,}]+)[^}]*line:\s*(\d+)[^}]*\}',
  );
  for (final m in fileLineRegex.allMatches(fm)) {
    final relPath = m.group(1)!.trim();
    final line = int.parse(m.group(2)!.trim());
    final referenced = File('$root/$relPath');
    if (!referenced.existsSync()) {
      return ValidationResult.fail(
        'file:line does not resolve — $relPath does not exist',
      );
    }
    final lineCount = referenced.readAsLinesSync().length;
    if (line < 1 || line > lineCount) {
      return ValidationResult.fail(
        'file:line does not resolve — $relPath line $line outside [1, $lineCount]',
      );
    }
  }

  return const ValidationResult.ok();
}
