// scripts/check_telemetry_pii_classification.dart
//
// Gate: 22
//
// Gate 22: every `ErrorTelemetry.recordNonFatal` / `logEvent` callsite
// in lib/ should be classified for PII risk. Advisory-only by default.
//
// Closes OI-42 lens L40 (PII / privacy in telemetry payloads). Designed
// to catch DPDP / GDPR risk class — `user_message`, `meal_name`,
// `image_url`, `food_name`, `coach_notes` in telemetry payloads.
//
// **Audit-only mode by default** — flips to strict with `--strict`
// flag. Initial-baseline tracking happens via OI-44 follow-up.
//
// Exit 0 always in default mode. Strict mode: exit 1 if any payload
// contains an unallowlisted user-text field.

import 'dart:io';

const _scanRoots = <String>[
  'lib/core/services',
  'lib/features',
  'lib/shared',
];

// Field names that, if present in a telemetry payload, MUST be
// explicitly allowlisted as the entry's PII classification.
const _piiSuspectFields = <String>[
  'user_message',
  'meal_name',
  'food_name',
  'image_url',
  'media_url',
  'coach_notes',
  'coaching_notes',
  'name',          // very broad; may false-positive
  'email',
  'phone',
];

// Allowlisted op_types that are PERMITTED to include user text in their
// payload bodies. Each entry needs a why-comment.
const _piiAllowedOpTypes = <String>{
  // Diagnostic events that intentionally include the user input for
  // root-cause analysis. Founder accepts the risk; review quarterly.
  'food_text_analysis_failure',
  'circuit_breaker_user_message_excerpt',
};

void main(List<String> args) {
  final strict = args.contains('--strict');
  final findings = <String>[];
  int total = 0;

  for (final root in _scanRoots) {
    final dir = Directory(root);
    if (!dir.existsSync()) continue;
    for (final entity in dir.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final src = entity.readAsStringSync();
      final path = entity.path.replaceAll('\\', '/');

      // Find recordNonFatal / logEvent callsites. Brace-balance the args.
      final telemetryRegex = RegExp(
        r'\b(ErrorTelemetry\.(recordNonFatal|logEvent))\s*\(',
      );
      for (final m in telemetryRegex.allMatches(src)) {
        total++;
        // Brace-balance the call's args.
        int depth = 1;
        int? closeIdx;
        for (int i = m.end; i < src.length && i < m.end + 2000; i++) {
          if (src[i] == '(') depth++;
          if (src[i] == ')') {
            depth--;
            if (depth == 0) {
              closeIdx = i;
              break;
            }
          }
        }
        if (closeIdx == null) continue;
        final argBody = src.substring(m.end, closeIdx);

        // Check for PII suspect fields. False-positive aware: skip when
        // the field name appears only in a comment.
        final stripped = argBody
            .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
            .replaceAll(RegExp(r'//[^\n]*'), '');

        for (final field in _piiSuspectFields) {
          // Match `'<field>'`/`"<field>"` (string key in a map literal).
          // The `name` field is too noisy — skip unless paired with
          // a clearly-user-text neighbour.
          if (field == 'name') continue;
          final fieldRegex = RegExp("['\"]" + field + "['\"]\\s*[:,]");
          if (fieldRegex.hasMatch(stripped)) {
            // Try to extract the op_type. Look for `reason: '...'` or
            // `op_type: '...'` in the args.
            // Match `reason: '<value>'` or `op_type: '<value>'` (Dart
            // uses single-quoted strings; that's the common case here).
            final opTypeMatch = RegExp(
                    r"(?:reason|op_type)\s*:\s*'([^']+)'")
                .firstMatch(stripped);
            final opType = opTypeMatch?.group(1) ?? '<unknown>';
            if (_piiAllowedOpTypes.contains(opType)) continue;
            findings.add(
                '$path:${_lineOf(src, m.start)} — telemetry call carries "$field" (op_type=$opType)');
          }
        }
      }
    }
  }

  stdout.writeln(
      '[Gate 22] scanned $total telemetry callsites; ${findings.length} suspect PII surfaces');
  if (findings.isEmpty) {
    stdout.writeln('[Gate 22] PASS');
    exit(0);
  }

  if (!strict) {
    stdout.writeln('[Gate 22] ADVISORY — sample findings (first 20):');
    for (final f in findings.take(20)) {
      stdout.writeln('  $f');
    }
    if (findings.length > 20) {
      stdout.writeln('  ... + ${findings.length - 20} more');
    }
    stdout.writeln(
        '[Gate 22] exit 0 (audit-only mode). Use --strict to fail. '
        'OI-44 tracks initial cleanup.');
    exit(0);
  }

  stderr.writeln('[Gate 22] STRICT — ${findings.length} unclassified PII surfaces:');
  for (final f in findings.take(50)) {
    stderr.writeln('  $f');
  }
  stderr.writeln(
      '\n  Fix: either remove the user-text field, OR add the call\'s '
      'op_type to _piiAllowedOpTypes with a clear reason.');
  exit(1);
}

int _lineOf(String src, int idx) {
  var line = 1;
  for (var i = 0; i < idx; i++) {
    if (src[i] == '\n') line++;
  }
  return line;
}
