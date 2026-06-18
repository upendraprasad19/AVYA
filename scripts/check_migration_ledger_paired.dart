// scripts/check_migration_ledger_paired.dart
//
// Gate (P1.G, discipline-overhaul 2026-06-18): assert that whenever a new
// migration SQL file is ADDED in the current staged set, the ledger file
// `backups/applied_migrations.json` is ALSO staged AND contains an entry
// whose `migration` field matches the NNN prefix of that file.
//
// Motivation: CLAUDE.md §4.5 requires "Migration apply paired with
// backups/applied_migrations.json update in same commit." Without this gate
// that rule was enforced only by agent discipline — no mechanical backstop.
// A migration committed without a ledger entry means the audit trail goes dark
// until someone manually notices; this gate closes that gap.
//
// Trigger condition:
//   A file matching `supabase/migrations/NNN_*.sql` appears as an ADDED (A)
//   entry in `git diff --cached --name-only --diff-filter=A`.
//
// No staged migration → PASS (no-op). Empty staged set (CI) → PASS.
// `--warn-only` supported: prints a warning but exits 0.
//
// Exit 0 = pass.
// Exit 1 = fail (migration staged without a matching ledger entry).

import 'dart:convert';
import 'dart:io';

const _ledgerPath = 'backups/applied_migrations.json';

void main(List<String> args) async {
  final warnOnly = args.contains('--warn-only');

  // ── Collect staged-added migration files ──────────────────────────────────
  final gitResult = await Process.run(
    'git',
    ['diff', '--cached', '--name-only', '--diff-filter=A'],
    stdoutEncoding: utf8,
  );

  if (gitResult.exitCode != 0) {
    // git not available or no repo — CI safety net: treat as no-op.
    stdout.writeln('[Gate-MLP] SKIP: git diff failed (no repo context).');
    exit(0);
  }

  final stagedFiles = (gitResult.stdout as String)
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .toList();

  // Match `supabase/migrations/NNN_*.sql` (NNN = 3+ digits).
  final migrationRegex =
      RegExp(r'^supabase/migrations/(\d{3,})_.*\.sql$', caseSensitive: false);

  final stagedMigrations = <String, String>{}; // NNN → full path
  for (final f in stagedFiles) {
    final m = migrationRegex.firstMatch(f);
    if (m != null) {
      stagedMigrations[m.group(1)!] = f;
    }
  }

  if (stagedMigrations.isEmpty) {
    // No staged migration additions — gate is not applicable.
    stdout.writeln('[Gate-MLP] PASS: no staged migration additions.');
    exit(0);
  }

  // ── Check ledger is also staged ───────────────────────────────────────────
  final ledgerStaged = stagedFiles.contains(_ledgerPath);
  if (!ledgerStaged) {
    final msg =
        '[Gate-MLP] FAIL: ${stagedMigrations.length} migration(s) staged but '
        '`$_ledgerPath` is NOT staged. Stage the ledger update in the same commit.';
    stderr.writeln(msg);
    stderr.writeln(
        '  Staged migrations: ${stagedMigrations.values.join(", ")}');
    exit(warnOnly ? 0 : 1);
  }

  // ── Parse ledger from disk ─────────────────────────────────────────────────
  final ledgerFile = File(_ledgerPath);
  if (!ledgerFile.existsSync()) {
    stderr.writeln('[Gate-MLP] FAIL: $_ledgerPath not found on disk.');
    exit(warnOnly ? 0 : 1);
  }

  List<dynamic> ledger;
  try {
    ledger = jsonDecode(ledgerFile.readAsStringSync()) as List<dynamic>;
  } catch (e) {
    stderr.writeln('[Gate-MLP] FAIL: cannot parse $_ledgerPath: $e');
    exit(warnOnly ? 0 : 1);
  }

  // Build a set of NNN prefixes already in the ledger.
  final ledgerNnns = <String>{};
  for (final entry in ledger) {
    if (entry is Map && entry['migration'] is String) {
      final raw = (entry['migration'] as String).trim();
      // Accept bare NNN ("093") or full filename ("093_foo.sql") alike.
      final prefixMatch = RegExp(r'^(\d{3,})').firstMatch(raw);
      if (prefixMatch != null) ledgerNnns.add(prefixMatch.group(1)!);
    }
  }

  // ── Assert every staged migration has a ledger entry ─────────────────────
  final missing = <String>[];
  for (final entry in stagedMigrations.entries) {
    if (!ledgerNnns.contains(entry.key)) {
      missing.add('NNN=${entry.key} (${entry.value})');
    }
  }

  final tag = warnOnly ? '[Gate-MLP WARN]' : '[Gate-MLP]';
  if (missing.isEmpty) {
    stdout.writeln('$tag PASS: all ${stagedMigrations.length} staged migration(s) '
        'have matching ledger entries.');
    exit(0);
  }

  stderr.writeln('$tag FAIL: ${missing.length} staged migration(s) have no '
      'matching entry in `$_ledgerPath`:');
  for (final m in missing) {
    stderr.writeln('  - $m');
  }
  stderr.writeln(
      'Add an entry with `migration: "<NNN>"` to the ledger and re-stage it.');
  exit(warnOnly ? 0 : 1);
}
