// scripts/check_applied_migrations_ledger.dart
//
// Gate: 39
//
// Gate 39 (Tech-debt audit 2026-05-20, finding I12): assert that
// `backups/applied_migrations.json` is in the structured-record shape
// `[{migration, applied_at, hash, applier}, ...]` — NOT the legacy
// bare-string-array shape.
//
// Pre-fix the ledger was a JSON array of migration IDs only. No audit
// trail for "when was 067 applied? by whom?" — schema-vs-code drift
// detection had to fall back to `mcp__supabase__list_migrations` calls
// every time. Structured ledger enables greppable history + integrity
// checks via the `hash` field.
//
// Run after every migration: `dart run scripts/migrate_applied_migrations_ledger.dart`
// is idempotent and brings the ledger up to date.
//
// Exit 0 = pass.
// Exit 1 = fail (any record missing required field).

import 'dart:convert';
import 'dart:io';

const _ledgerPath = 'backups/applied_migrations.json';
const _requiredKeys = ['migration', 'applied_at', 'hash', 'applier'];

void main(List<String> args) async {
  final warnOnly = args.contains('--warn-only');
  final file = File(_ledgerPath);
  if (!file.existsSync()) {
    stderr.writeln('[Gate 39] FAIL: $_ledgerPath not found');
    exit(warnOnly ? 0 : 1);
  }
  final content = file.readAsStringSync();
  final parsed = jsonDecode(content);
  if (parsed is! List) {
    stderr.writeln('[Gate 39] FAIL: $_ledgerPath is not a JSON array');
    exit(warnOnly ? 0 : 1);
  }

  final violations = <String>[];

  // Legacy bare-string detection.
  if (parsed.isEmpty) {
    // Empty array — allowed (no migrations applied yet).
  } else if (parsed.first is String) {
    violations.add('LEGACY SHAPE: $_ledgerPath is a string array, not record array. '
        'Run `dart run scripts/migrate_applied_migrations_ledger.dart` to migrate.');
  } else {
    // Verify each record has all required keys + non-empty values.
    for (var i = 0; i < parsed.length; i++) {
      final entry = parsed[i];
      if (entry is! Map) {
        violations.add('row $i: not a Map');
        continue;
      }
      for (final key in _requiredKeys) {
        if (!entry.containsKey(key)) {
          violations.add('row $i ($entry): missing key `$key`');
        } else {
          final value = entry[key];
          if (value == null || (value is String && value.isEmpty)) {
            violations.add('row $i (${entry['migration']}): key `$key` is null/empty');
          }
        }
      }
    }
  }

  final tag = warnOnly ? '[Gate 39 WARN]' : '[Gate 39]';
  if (violations.isEmpty) {
    stdout.writeln('$tag PASS: ledger has ${parsed.length} structured records.');
    exit(0);
  }
  stderr.writeln('$tag FAIL: ${violations.length} violation(s):');
  for (final v in violations.take(10)) {
    stderr.writeln('  - $v');
  }
  if (violations.length > 10) stderr.writeln('  ... and ${violations.length - 10} more');
  exit(warnOnly ? 0 : 1);
}
