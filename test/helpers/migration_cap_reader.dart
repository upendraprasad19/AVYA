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
      // ⚠ Must accept BOTH `FUNCTION foo` and `FUNCTION public.foo` — the repo
      // uses both conventions (111/114/127 bare, 128 qualified), and a
      // substring test for the bare form silently MISSES a qualified
      // redefinition. That is not hypothetical: migration 129 was written
      // qualified, and this resolver kept returning 114 for the vision
      // function, so the parity test would have read a SUPERSEDED migration
      // and passed. Caught by the §7 step-0b dry-run, before the live apply.
      // ⚠ Anchored on CREATE. Without it, `ALTER FUNCTION <name> SET
      // search_path` counts as a "definition" — migration 090 does exactly
      // that to enforce_food_text_daily_limit, and only the accident that
      // 129 > 090 kept it from winning the latest-wins contest. A future ALTER
      // numbered above the real definer would resolve to a file containing no
      // function body at all, and functionBlock would return null into a
      // forced unwrap.
      .where((f) => RegExp(
                'CREATE\\s+(?:OR\\s+REPLACE\\s+)?FUNCTION\\s+'
                '(?:public\\.)?$functionName\\b',
              ).hasMatch(stripSqlComments(f.readAsStringSync())))
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

/// The `CREATE OR REPLACE FUNCTION <name> ... $$` block for ONE function,
/// comment-stripped. Returns null when the file does not define it.
///
/// ⚠ Scoping is NOT cosmetic. Both cap readers below used to `firstMatch` over
/// the WHOLE file, and migration 111 defines BOTH `enforce_chat_app_daily_limit`
/// (`daily_count >= 10`, :53) and `enforce_vision_analysis_daily_limit`
/// (`>= 15`, :90) — so an unscoped read of 111 for VISION returns the CHAT cap.
/// That was live and latent, masked only by the accident that 114 and 127 are
/// single-function files. Migration 129 defines all three at once, which would
/// have made it reachable. This is the CLAUDE.md §4.9 "last CREATE OR REPLACE
/// wins" trap in its second form: right file, wrong function.
///
/// Every body in this repo opens `AS $$` and closes `$$;` with one consistent
/// tag and no nested dollar-quoting (verified across 111/114/127/128/129).
String? functionBlock(String sql, String functionName) {
  final body = stripSqlComments(sql);
  final start = RegExp(
    'CREATE\\s+(?:OR\\s+REPLACE\\s+)?FUNCTION\\s+(?:public\\.)?$functionName\\b',
  ).firstMatch(body);
  if (start == null) return null;
  final rest = body.substring(start.start);

  // ⚠ Match the ACTUAL dollar-quote tag and close on the SAME one. Every
  // migration here uses a bare `$$` today, but Postgres allows `$function$`,
  // `$body$` and so on — and the earlier version took the first `$$` it saw,
  // so a `$function$`-tagged body followed by a later bare-`$$` function
  // returned one long block spanning BOTH. That is the exact "right file,
  // wrong function" class this helper exists to prevent, reintroduced inside
  // the fix for it (B-pass on `004af467`). Latent today; not left latent.
  final tag = RegExp(r'\$([A-Za-z_][A-Za-z0-9_]*)?\$').firstMatch(rest);
  if (tag == null) return null;
  final delim = tag.group(0)!;
  final close = rest.indexOf(delim, tag.end);
  if (close < 0) return null;
  return rest.substring(0, close + delim.length);
}

/// Reads the `daily_cap := CASE WHEN is_pro THEN <pro> ELSE <free> END`
/// expression from ONE function's block. Returns null when the shape is absent.
({int pro, int free})? readProFreeCap(File migration, String functionName) {
  final block = functionBlock(migration.readAsStringSync(), functionName);
  if (block == null) return null;
  final m = RegExp(
    r'daily_cap\s*:=\s*CASE\s+WHEN\s+is_pro\s+THEN\s+(\d+)\s+ELSE\s+(\d+)\s+END',
  ).firstMatch(block);
  if (m == null) return null;
  return (pro: int.parse(m.group(1)!), free: int.parse(m.group(2)!));
}

/// Reads the single daily ceiling out of ONE function's block, in either of the
/// two shapes this repo has used. Returns null when neither is present.
///
/// * pre-129: `IF daily_count >= <n> THEN` — the count-then-compare form.
/// * 129 and later: the integer literal passed as `consume_quota(...)`'s
///   `p_limit`. The cap moved into the call when the `count(*)` disappeared.
///
/// Both are kept deliberately: the mutation proof for the scoping fix points
/// this reader at migration 111, which only has the legacy shape.
///
/// ⚠ Deliberately NOT sourced from the `(cap=N)` RAISE suffix. Nothing reads
/// that suffix at runtime — ai-proxy matches the bare identifier — and taking
/// the cap from it would quietly make it load-bearing again.
int? readSingleCeiling(File migration, String functionName) {
  final block = functionBlock(migration.readAsStringSync(), functionName);
  if (block == null) return null;
  final legacy = RegExp(r'daily_count\s*>=\s*(\d+)').firstMatch(block);
  if (legacy != null) return int.parse(legacy.group(1)!);
  final consumed =
      RegExp(r'consume_quota\s*\([^;]*?,\s*(\d+)\s*\)').firstMatch(block);
  return consumed == null ? null : int.parse(consumed.group(1)!);
}
