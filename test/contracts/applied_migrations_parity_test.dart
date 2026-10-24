// test/contracts/applied_migrations_parity_test.dart
//
// Contract (E.13 — Audit 2026-05-16 framework deliverable):
// Every `*.sql` file in supabase/migrations/ must have its version
// recorded in backups/applied_migrations.json.
//
// Detect both numeric (`001`, `050b`) and timestamp
// (`20260328000001`) version shapes.
//
// The INVERSE direction (every entry has a file) is NOT enforced:
// some historical entries (e.g. "024") were inlined into other
// migrations on apply; the JSON is a forward-only audit log.
//
// See CLAUDE.md `feedback_migration_apply_record_pair.md` —
// every `apply_migration` MCP call must be paired with a
// applied_migrations.json update in the same commit.

import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every supabase/migrations/*.sql is in backups/applied_migrations.json',
      () {
    final migrationsDir = Directory('supabase/migrations');
    expect(migrationsDir.existsSync(), isTrue,
        reason: 'supabase/migrations/ must exist');

    final jsonFile = File('backups/applied_migrations.json');
    expect(jsonFile.existsSync(), isTrue,
        reason: 'backups/applied_migrations.json must exist');

    // Schema migration (2026-05-XX): applied_migrations.json used to be
    // a JSON array of bare version strings. It now stores a list of
    // entry objects (`{migration, applied_at, hash, applier, ...}`) so
    // we can audit who applied what + recompute hashes on drift. Read
    // the `migration` field per entry if present; fall back to the bare
    // string shape for back-compat with older snapshots.
    final raw = jsonDecode(jsonFile.readAsStringSync()) as List;
    final applied = raw
        .map((e) => e is String ? e : (e as Map)['migration'] as String)
        .toSet();

    // Extract version from filename for both shapes:
    //   001_foo.sql           → "001"
    //   050b_foo.sql          → "050b"
    //   20260328000001_foo.sql → "20260328000001"
    final versionRegex = RegExp(r'^(\d+[a-z]?|\d{14})_');

    final missing = <String>[];

    for (final entity in migrationsDir.listSync()) {
      if (entity is! File) continue;
      if (!entity.path.endsWith('.sql')) continue;
      final name = entity.path.replaceAll('\\', '/').split('/').last;
      // Skip combined / reconciliation files — not real migrations.
      if (name == 'all_migrations_combined.sql') continue;

      final m = versionRegex.firstMatch(name);
      if (m == null) {
        // Could be a README — skip.
        continue;
      }
      final version = m.group(1)!;
      if (!applied.contains(version)) {
        missing.add('$name (version=$version)');
      }
    }

    expect(
      missing,
      isEmpty,
      reason:
          'Migration files NOT recorded in backups/applied_migrations.json:\n'
          '  ${missing.take(10).join("\n  ")}\n\n'
          'Fix: append the version string to backups/applied_migrations.json\n'
          'in the same commit as the new migration. See CLAUDE.md \n'
          '`feedback_migration_apply_record_pair.md`.',
    );
  });
}
