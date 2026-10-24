// scripts/blast_radius_content_rules_lib.dart
//
// Content-aware escalation rules for the blast-radius classifier. Plugged
// into all THREE scripts that independently duplicate the whole path-glob
// engine — `blast_radius_from_diff.dart`, `check_plan_review_record_exists.dart`,
// and `check_code_review_pass_exists.dart` (the last is a BLOCKING local
// pre-commit gate, not just informational — missing it would be the most
// load-bearing gap, not the least). Patching only some leaves the others
// blind; see test/contracts/blast_radius_content_rule_wired_all_scripts_test.dart.
//
// docs/blast_radius.yaml's catastrophic tier for migrations is filename-
// substring-based (`*security_definer*.sql`, `*rls*.sql`, ...). A migration
// that grants elevated/anon-executable permissions via `SECURITY DEFINER`
// but has an innocuous filename (e.g. `106_email_is_registered_check.sql`)
// slips through at whatever the path-only tier resolves to (usually
// `platform`, per the `supabase/migrations/**` catch-all). This escalates
// by CONTENT instead of trusting the filename.
//
// Injectable I/O (fileExists/readFile) for unit testing without real disk
// access; defaults to real `File` calls.

import 'dart:io';

/// A path is eligible for content scanning if it's a `.sql` file under
/// `supabase/migrations/` (any depth — the `041_chunks/` sub-directory
/// holds real migration content split into row-batch files).
bool isMigrationSqlPath(String path) {
  final normalized = path.replaceAll('\\', '/');
  return normalized.startsWith('supabase/migrations/') &&
      normalized.endsWith('.sql');
}

/// Matches `SECURITY DEFINER` with arbitrary whitespace between the two
/// words, case-insensitive — the exact Postgres syntax this repo's own
/// migrations use (grep-confirmed against 20 existing SECURITY DEFINER
/// migrations, e.g. `053_security_definer_hardening.sql`).
bool containsSecurityDefiner(String content) =>
    RegExp(r'security\s+definer', caseSensitive: false).hasMatch(content);

/// True if [path] should force the `catastrophic` tier regardless of what
/// the path-glob rules in `docs/blast_radius.yaml` say.
///
/// Fails OPEN (returns false) when the path isn't an eligible migration
/// file, when the file no longer exists (deleted-in-diff — nothing to
/// scan), or when it's unreadable — a content check can only ESCALATE, so
/// erring toward "no escalation" on missing/unreadable input is the safe
/// direction (it never suppresses a filename-based catastrophic match,
/// since callers OR this result into their own tier computation).
///
/// [fileExists] / [readFile] are injectable for tests; production callers
/// omit them and get real `File` I/O.
bool contentForcesCatastrophic(
  String path, {
  bool Function(String path)? fileExists,
  String Function(String path)? readFile,
}) {
  if (!isMigrationSqlPath(path)) return false;
  final exists = fileExists ?? (p) => File(p).existsSync();
  if (!exists(path)) return false;
  final String content;
  try {
    content = readFile != null ? readFile(path) : File(path).readAsStringSync();
  } catch (_) {
    return false;
  }
  return containsSecurityDefiner(content);
}
