// scripts/validate_agent_diagnose_stanza_lib.dart
//
// Pure validation logic for agent diagnose stanzas — importable by tests
// without spawning a subprocess.
//
// The agent output is free-form text. A stanza is delimited by the literal
// `diagnose_stanza:` key at column 0, followed by all indented lines until
// the next column-0 non-blank line or EOF.

const stanzaRequiredFields = <String>[
  'symptom',
  'concept',
  'writers',
  'readers',
  'hive_key_prefix',
  'hive_key_formula',
  'sync_methods',
  'restore_methods',
  'cloud_table',
  'cloud_columns',
  'contract_test_path',
  'ist_handling',
  'provider_invalidations',
  'telemetry_op_types',
  'cross_account_guard',
  'forbidden_patterns_checked',
  'proposed_fix',
  'regression_test_planned',
];

const placeholderPatterns = <String>[
  'TBD',
  'TODO',
  '<...>',
  '???',
  'tbd',
  'todo',
];

/// Result of validating an agent diagnose stanza.
class ValidationResult {
  final bool isValid;
  final String? error;

  const ValidationResult.ok()
      : isValid = true,
        error = null;
  const ValidationResult.fail(this.error) : isValid = false;
}

/// Validate a raw agent output [content] string.
///
/// Looks for a `diagnose_stanza:` block at column 0, then validates that all
/// 18 required fields are present and no placeholder values appear.
ValidationResult validateAgentDiagnoseStanza(String content) {
  // Normalize line endings (CRLF → LF) so the regex works on Windows.
  content = content.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

  // Find the stanza: `diagnose_stanza:` at column 0, then capture all lines
  // that are indented (start with at least one space/tab) until the next
  // non-indented line or EOF.
  final stanzaMatch = RegExp(
    r'^diagnose_stanza:\s*\n((?:^[ \t]+.*\n?)*)',
    multiLine: true,
  ).firstMatch(content);

  if (stanzaMatch == null) {
    return const ValidationResult.fail(
        'no diagnose_stanza found in agent output');
  }
  final stanza = stanzaMatch.group(1)!;

  // 1. Required field presence — each field must appear indented under the
  //    stanza as `  fieldname:` (one or more leading spaces).
  for (final field in stanzaRequiredFields) {
    if (!RegExp(
      r'^\s+' + RegExp.escape(field) + r':',
      multiLine: true,
    ).hasMatch(stanza)) {
      return ValidationResult.fail('stanza missing required field: $field');
    }
  }

  // 2. Placeholder scan.
  for (final p in placeholderPatterns) {
    if (stanza.contains(p)) {
      return ValidationResult.fail('stanza placeholder detected: $p');
    }
  }

  return const ValidationResult.ok();
}
