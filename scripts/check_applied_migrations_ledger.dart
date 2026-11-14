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
// OI-135 + OI-137 (2026-09-29): the `hash` VALUE is now verified, not just its presence.
// Shape must be `sha256:<64 hex>` or an `unverifiable:<reason>` sentinel (a literal
// `sha256:%s` once passed this gate), and a real hash must equal the sha256 of the
// migration file under its LF or CRLF form. Logic lives in
// migration_ledger_hash_lib.dart (pure, no package deps — this runs on every commit and a
// fresh worktree has no .dart_tool). Five historical drifts are grandfathered BY NAME with
// a pinned sha there. LIMITS, stated plainly: it catches a FORGOTTEN re-stamp, not a
// deliberate edit + re-stamp in one commit; and it reads the WORKING TREE, not the staged
// blobs, so with partial staging it can verify bytes that are not what gets committed
// (CI verifies the committed tree).
//
// Exit 0 = pass.
// Exit 1 = fail (any record missing required field, malformed hash, or hash drift).

import 'dart:convert';
import 'dart:io';

import 'migration_ledger_hash_lib.dart';

const _ledgerPath = 'backups/applied_migrations.json';
const _migrationsDir = 'supabase/migrations';
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

  // Hash VALUE verification (OI-135 / OI-137). Only meaningful once the shape check above
  // has found record-shaped entries.
  if (violations.isEmpty && parsed.isNotEmpty && parsed.first is Map) {
    final files = <String, List<int>>{};
    final dir = Directory(_migrationsDir);
    if (dir.existsSync()) {
      for (final e in dir.listSync()) {
        if (e is File && e.path.endsWith('.sql')) {
          files[e.uri.pathSegments.last] = e.readAsBytesSync();
        }
      }
    }
    violations.addAll(verifyLedgerHashes(
      parsed.cast<Map<String, dynamic>>(),
      files,
    ));
  }

  final tag = warnOnly ? '[Gate 39 WARN]' : '[Gate 39]';
  if (violations.isEmpty) {
    stdout.writeln('$tag PASS: ledger has ${parsed.length} structured records; hashes verified (${grandfatheredLedgerHashDrift.length} grandfathered by name).');
    exit(0);
  }
  stderr.writeln('$tag FAIL: ${violations.length} violation(s):');
  for (final v in violations.take(10)) {
    stderr.writeln('  - $v');
  }
  if (violations.length > 10) stderr.writeln('  ... and ${violations.length - 10} more');
  exit(warnOnly ? 0 : 1);
}
