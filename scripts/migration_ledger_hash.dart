// scripts/migration_ledger_hash.dart
//
// Prints the ledger-ready hash for a migration file: `sha256:<hex>` of its LF form —
// the ONE canonical form new `backups/applied_migrations.json` entries are written in
// (Gate 39 also accepts the CRLF form, but never write it).
//
// Usage: dart run scripts/migration_ledger_hash.dart <NNN | NNNx | path/to/file.sql>
//
// Exists because a raw `sha256sum` on a CRLF working copy is exactly how 56 ledger
// entries came to disagree with their files (OI-135). This CLI hashes the normalised
// bytes, so the answer is the same on every machine.
//
// Exit 0 = printed. 64 = usage. 2 = no such file / ambiguous id.

import 'dart:io';

import 'migration_ledger_hash_lib.dart';

void main(List<String> args) {
  if (args.length != 1) {
    stderr.writeln('usage: dart run scripts/migration_ledger_hash.dart <NNN|NNNx|path.sql>');
    exit(64);
  }
  final arg = args.single;
  File file;
  if (arg.endsWith('.sql')) {
    file = File(arg);
  } else {
    final dir = Directory('supabase/migrations');
    final names = dir.existsSync()
        ? dir.listSync().whereType<File>().map((f) => f.uri.pathSegments.last).toList()
        : <String>[];
    final matches = resolveMigrationFiles(arg, null, names);
    if (matches.length != 1) {
      stderr.writeln(matches.isEmpty
          ? 'no top-level supabase/migrations/${arg}_*.sql'
          : 'ambiguous id $arg: ${matches.join(', ')} — pass the file path');
      exit(2);
    }
    file = File('supabase/migrations/${matches.single}');
  }
  if (!file.existsSync()) {
    stderr.writeln('no such file: ${file.path}');
    exit(2);
  }
  stdout.writeln(canonicalLedgerHash(file.readAsBytesSync()));
}
