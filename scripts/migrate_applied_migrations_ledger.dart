// scripts/migrate_applied_migrations_ledger.dart
//
// One-shot conversion (audit 2026-05-20 / I12): rewrite
// `backups/applied_migrations.json` from string-array shape to structured
// record shape with `migration`, `applied_at`, `hash`, `applier` fields.
//
// For historical entries:
//   - migration: ID as-is from current array
//   - applied_at: first commit timestamp that touched the matching .sql file
//                 (via `git log -1 --format=%aI --reverse -- <path>`)
//   - hash: sha256 of the .sql file content
//   - applier: 'founder' (all historical entries are founder-applied)
//
// Idempotent: if the file is already in record shape, it's left untouched.
//
// Run once: `dart run scripts/migrate_applied_migrations_ledger.dart`

import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';

const _migrationsDir = 'supabase/migrations';
const _ledgerPath = 'backups/applied_migrations.json';

Future<void> main() async {
  final ledgerFile = File(_ledgerPath);
  if (!ledgerFile.existsSync()) {
    stderr.writeln('ERROR: $_ledgerPath not found');
    exit(1);
  }

  final raw = ledgerFile.readAsStringSync();
  final parsed = jsonDecode(raw);

  if (parsed is! List) {
    stderr.writeln('ERROR: $_ledgerPath is not a JSON array');
    exit(1);
  }

  // Detect shape — if first non-empty element is a Map, already structured.
  if (parsed.isNotEmpty && parsed.first is Map) {
    stdout.writeln('IDEMPOTENT: $_ledgerPath is already in record shape (${parsed.length} entries). No-op.');
    exit(0);
  }

  if (parsed.isEmpty || parsed.first is! String) {
    stderr.writeln('ERROR: unexpected ledger shape');
    exit(1);
  }

  final records = <Map<String, Object?>>[];
  for (final entry in parsed.cast<String>()) {
    final migrationFile = await _findMigrationFile(entry);
    String? hash;
    String? appliedAt;
    if (migrationFile != null) {
      hash = await _sha256(migrationFile);
      appliedAt = await _firstCommitTimestamp(migrationFile.path);
    }
    records.add({
      'migration': entry,
      'applied_at': appliedAt ?? '2026-04-15T08:00:00Z', // safe default — earliest project commit era
      'hash': hash != null ? 'sha256:$hash' : null,
      'applier': 'founder',
    });
  }

  // Emit pretty JSON (2-space indent).
  final encoder = const JsonEncoder.withIndent('  ');
  ledgerFile.writeAsStringSync('${encoder.convert(records)}\n');
  stdout.writeln('CONVERTED: $_ledgerPath now has ${records.length} structured records.');
}

Future<File?> _findMigrationFile(String migrationId) async {
  // Match `<id>_*.sql` or `<id>.sql` exactly.
  final dir = Directory(_migrationsDir);
  if (!dir.existsSync()) return null;
  for (final entity in dir.listSync()) {
    if (entity is! File) continue;
    final name = entity.path.split(RegExp(r'[\\/]')).last;
    if (name.startsWith('${migrationId}_') || name == '$migrationId.sql') {
      return entity;
    }
  }
  return null;
}

Future<String> _sha256(File f) async {
  final bytes = await f.readAsBytes();
  return sha256.convert(bytes).toString();
}

Future<String?> _firstCommitTimestamp(String path) async {
  try {
    final result = await Process.run(
      'git',
      ['log', '--diff-filter=A', '--format=%aI', '-1', '--', path],
      runInShell: true,
    );
    final out = (result.stdout as String).trim();
    return out.isEmpty ? null : out;
  } catch (_) {
    return null;
  }
}
