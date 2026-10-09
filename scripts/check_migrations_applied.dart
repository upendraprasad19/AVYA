// scripts/check_migrations_applied.dart
//
// Gate: 14
//
// Gate 14: Local migrations match the prod state snapshot.
//
// Reads supabase/migrations/*.sql filenames, compares against
// backups/applied_migrations.json (a manually maintained snapshot).
//
// If the snapshot doesn't exist → exit 0 with a warning.
// If listed migrations diverge → exit 1 listing unapplied ones.
//
// TODO: Wire this up to live Supabase MCP query (project dedsavbjuwgarrhphgnl)
// once MCP tooling is available at build time. Until then this is a snapshot-
// based comparison.
//
// Initialization: backups/applied_migrations.json is committed alongside this
// script with the known-applied set as of 2026-05-10.
//
// Usage: dart run scripts/check_migrations_applied.dart

import 'dart:convert';
import 'dart:io';

import 'migration_collision_lib.dart';

void main(List<String> args) async {
  final projectRoot = Directory.current.path;
  final migrationsDir = Directory('$projectRoot/supabase/migrations');
  final snapshotPath = '$projectRoot/backups/applied_migrations.json';

  // ── 1. List local migrations ───────────────────────────────────────────────

  if (!migrationsDir.existsSync()) {
    stderr.writeln(
        '[Gate 14] WARN — supabase/migrations/ not found. Exit 0.');
    exit(0);
  }

  // Collect the numeric prefix / name for each .sql file.
  // Exclude the 041_chunks directory and any non-.sql entries.
  final localMigrations = <String>[];
  for (final entity in migrationsDir.listSync()) {
    if (entity is File && entity.path.endsWith('.sql')) {
      // Basename without path, e.g. "050_workout_templates_unique_user_name.sql"
      final name = entity.path.split(RegExp(r'[/\\]')).last;
      // Exclude combined files like "all_migrations_combined.sql"
      if (!name.startsWith('all_')) {
        localMigrations.add(name);
      }
    }
  }
  localMigrations.sort();

  stdout.writeln('[Gate 14] Local migrations (${localMigrations.length}):');
  for (final m in localMigrations) {
    stdout.writeln('  $m');
  }

  // ── 1b. Collision check (OI-255) ───────────────────────────────────────────
  //
  // Two files can share the same bare numeric prefix when two branches each
  // independently pick "the next free number" off their own diverged view of
  // `main`. The "unapplied" check below cannot see this: `a.startsWith(prefix)`
  // is satisfied by EITHER colliding file's applied-snapshot entry, so both
  // pass silently. This is a separate, stricter check for exactly that shape.
  final collisions = findMigrationPrefixCollisions(localMigrations);
  if (collisions.isNotEmpty) {
    stderr.writeln('\n[Gate 14] FAIL — migration number collision(s):');
    for (final entry in collisions.entries) {
      stderr.writeln('  "${entry.key}" claimed by: ${entry.value.join(', ')}');
    }
    stderr.writeln(
        '\n  Fix: rename one file to the next free bare number before'
        ' committing. Re-derive it fresh from origin/main plus any active'
        ' sibling branch — do not trust the local tree alone (OI-255).');
    exit(1);
  }

  // ── 2. Load snapshot ──────────────────────────────────────────────────────

  final snapshotFile = File(snapshotPath);
  if (!snapshotFile.existsSync()) {
    stderr.writeln(
        '\n[Gate 14] WARN — backups/applied_migrations.json not found.'
        ' Cannot verify prod state. Exit 0.');
    stderr.writeln(
        '  Initialize by running: dart run scripts/check_migrations_applied.dart --init');
    exit(0);
  }

  late List<String> appliedMigrations;
  try {
    final raw = jsonDecode(snapshotFile.readAsStringSync()) as List<dynamic>;
    // Schema changed 2026-05-11: entries went from bare String to object
    // `{"migration": "<id>", "applied_at": "...", "hash": "...", ...}`.
    // Support both shapes — extract the migration id whatever the shape.
    appliedMigrations = raw.map((entry) {
      if (entry is String) return entry;
      if (entry is Map) {
        final id = entry['migration'];
        if (id is String) return id;
        throw FormatException(
          'applied_migrations.json entry missing string `migration` field: $entry',
        );
      }
      throw FormatException(
        'applied_migrations.json entry has unexpected type ${entry.runtimeType}: $entry',
      );
    }).toList();
  } catch (e) {
    stderr.writeln(
        '[Gate 14] ERROR — could not parse backups/applied_migrations.json: $e');
    exit(1);
  }

  // ── 3. Compare ────────────────────────────────────────────────────────────

  // "Unapplied" = in local migrations but not in the snapshot.
  final unapplied = localMigrations.where((m) {
    // Match by the numeric prefix (first segment before _).
    final prefix = m.split('_').first;
    return !appliedMigrations
        .any((a) => a.startsWith(prefix) || a == m.replaceAll('.sql', ''));
  }).toList();

  // ── 4. Report ─────────────────────────────────────────────────────────────

  if (unapplied.isEmpty) {
    stdout.writeln('\n[Gate 14] PASS — all local migrations appear in the'
        ' applied snapshot (${appliedMigrations.length} applied).');
    exit(0);
  } else {
    stderr.writeln('\n[Gate 14] FAIL — ${unapplied.length} local migration(s)'
        ' not found in applied snapshot:');
    for (final m in unapplied) {
      stderr.writeln('  UNAPPLIED: $m');
    }
    stderr.writeln(
        '\n  Fix: apply the migration(s) via Supabase MCP or dashboard,'
        ' then update backups/applied_migrations.json.');
    stderr.writeln(
        '  Or if this is a new migration just written (not yet applied),'
        ' that is expected — apply it before shipping the APK.');
    exit(1);
  }
}
