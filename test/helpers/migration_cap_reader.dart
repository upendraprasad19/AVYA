// test/helpers/migration_cap_reader.dart
//
// Shared source readers for client<->server LIMIT PARITY contracts (b8f4c2).
//
// ⚠ THE WHOLE POINT OF THIS FILE: a server-side cap must be read from the
// HIGHEST-NUMBERED migration that defines its trigger function, never from the
// migration that first created it. `CREATE OR REPLACE` makes
// supabase/migrations/ append-only, so a single function has several
// definitions and only the last one is live:
//
//   enforce_food_text_daily_limit        -> 026, 113, 127   (live: 127)
//   enforce_vision_analysis_daily_limit  -> 111, 114        (live: 114)
//
// Reading an earlier one is stale BY CONSTRUCTION. That is not hypothetical:
// during the b8f4c2 batch, migration 111's vision cap (15) was read from source
// and reported to the founder as a correction to an earlier claim of 20 — three
// weeks after migration 114 had replaced it with exactly 20. Worse, 111 defines
// BOTH cap functions, so a naive first-match there returns the CHAT cap (10) for
// a vision query: a stale citation can hand you a number from a different
// feature entirely.
//
// Lives in test/helpers/ (alongside read_screen_source.dart) so the two parity
// contracts share ONE resolver. Duplicating it would invite the very drift these
// tests exist to catch.
//
// Pure by design — no `expect`, no test dependency. Callers assert.

import 'dart:io';

/// Strips SQL line comments (`--` to end of line).
///
/// Load-bearing in the CAP READERS, and not for the obvious reason. Every
/// migration in this family carries a commented-out rollback body holding the
/// PREVIOUS cap value, but that sits below the live statement so a first-match
/// would miss it anyway. The real trap is the FOUR-TAG HEADER: migration 127's
/// `Rollback strategy:` line quotes
/// `daily_cap := CASE WHEN is_pro THEN 200 ELSE 50 END;` at line 32, *above*
/// the live `ELSE 10` at line 65. Un-stripped, a first-match reads the rollback
/// prose as the live cap. Documenting the old value in a header makes the file
/// self-trapping for any naive grep. Mutation-proven: removing it from
/// [readProFreeCap] / [readSingleCeiling] reddens 1 test.
///
/// ⚠ Its use inside [latestMigrationDefining] is DEFENSIVE ONLY — mutation-
/// tested and reddened NOTHING, stated plainly so nobody credits it with more
/// than it does. Today every migration mentioning one of these functions also
/// defines it, so stripping changes the selection not at all. It guards the
/// future migration that merely *references* a function in prose, which would
/// otherwise be picked as the latest "definition" and then fail to parse.
String stripSqlComments(String s) => s
    .split('\n')
    .map((l) {
      final i = l.indexOf('--');
      return i >= 0 ? l.substring(0, i) : l;
    })
    .join('\n');

/// Strips Dart block and line comments.
String stripDartComments(String s) {
  final noBlock = s.replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '');
  return noBlock
      .split('\n')
      .map((l) {
        final i = l.indexOf('//');
        return i >= 0 ? l.substring(0, i) : l;
      })
      .join('\n');
}

/// Leading numeric prefix of a migration filename (`127_foo.sql` -> 127).
/// Returns -1 for a filename with no numeric prefix, which sorts it first and
/// therefore never wins the "latest" contest.
int migrationNumber(String basename) {
  final m = RegExp(r'^(\d+)').firstMatch(basename);
  return m == null ? -1 : int.parse(m.group(1)!);
}

/// The LIVE definition of a Postgres function: the highest-numbered migration
/// whose (comment-stripped) body declares it. Returns null when none does.
File? latestMigrationDefining(
  String functionName, {
  String migrationsDir = 'supabase/migrations',
}) {
  final dir = Directory(migrationsDir);
  if (!dir.existsSync()) return null;
  final defs = dir
      .listSync()
      .whereType<File>()
      .where((f) => f.uri.pathSegments.last.endsWith('.sql'))
      .where((f) => stripSqlComments(f.readAsStringSync())
          .contains('FUNCTION $functionName'))
      .toList();
  if (defs.isEmpty) return null;
  defs.sort((a, b) => migrationNumber(a.uri.pathSegments.last)
      .compareTo(migrationNumber(b.uri.pathSegments.last)));
  return defs.last;
}

/// Reads an `int` constant out of app_constants.dart. Null when absent.
int? clientIntConstant(
  String name, {
  String path = 'lib/core/constants/app_constants.dart',
}) {
  final src = stripDartComments(File(path).readAsStringSync());
  final m = RegExp('$name\\s*=\\s*(\\d+)').firstMatch(src);
  return m == null ? null : int.parse(m.group(1)!);
}

/// Reads the `daily_cap := CASE WHEN is_pro THEN <pro> ELSE <free> END`
/// expression from a migration body. Returns null when the shape is absent.
({int pro, int free})? readProFreeCap(File migration) {
  final body = stripSqlComments(migration.readAsStringSync());
  final m = RegExp(
    r'daily_cap\s*:=\s*CASE\s+WHEN\s+is_pro\s+THEN\s+(\d+)\s+ELSE\s+(\d+)\s+END',
  ).firstMatch(body);
  if (m == null) return null;
  return (pro: int.parse(m.group(1)!), free: int.parse(m.group(2)!));
}

/// Reads the single `daily_count >= <n>` ceiling from a migration body.
/// Returns null when absent.
int? readSingleCeiling(File migration) {
  final body = stripSqlComments(migration.readAsStringSync());
  final m = RegExp(r'daily_count\s*>=\s*(\d+)').firstMatch(body);
  return m == null ? null : int.parse(m.group(1)!);
}
