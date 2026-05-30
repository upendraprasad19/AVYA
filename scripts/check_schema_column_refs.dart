// scripts/check_schema_column_refs.dart
//
// Gate — Supabase column-reference validation against the live schema.
//
// THE STRUCTURAL ANSWER to "why do bugs survive our audits?": every prior
// audit was static (code-read + mock-data unit tests + targeted schema
// queries). None cross-checked the *column string literals* in client queries
// against the real Postgres catalog. That blind spot produced THREE wrong-
// column bugs in the 2026-05-30 web-E2E batch alone:
//   - e2a4f7  user_profile.full_name  (column lives on `users`)
//   - f4b2c9  rank_promotions.created_at + client_errors.message/severity (trigger)
//   - a7c3e1  daily_steps.total_steps + sleep_logs.hours (this gate's founding case)
// All three were the SAME class: a *plausible* column name that never matched
// the DDL, throwing 42703 at runtime and silently degrading.
//
// This gate extracts every PostgREST column reference in lib/ —
//   .from('<table>') ... .select('<cols>') / .eq('<col>', ) / .neq / .gt / .gte
//   / .lt / .lte / .like / .ilike / .order('<col>', ) / .contains('<col>', )
// — and validates each <col> against backups/live_schema_columns.json for that
// <table>. A reference to a non-existent column (or a non-existent table that
// isn't a known storage bucket) hard-fails.
//
// SCOPE / LIMITS (honest):
//   - Validates string-literal columns in select()/filter()/order() only. It
//     does NOT yet parse insert()/update()/upsert() map-literal keys (multi-
//     line maps + spreads + computed keys are false-positive-prone). Those
//     remain covered by sync round-trip contract tests. Future extension.
//   - select('*') / select() / embedded resource selects ('*, child(*)') skip
//     column validation (PostgREST resource embedding, not flat columns).
//   - supabase.storage.from('<bucket>') is skipped via the storage_buckets
//     allowlist in the snapshot.
//
// REGENERATING THE SNAPSHOT (do this in the SAME commit as any migration that
// adds/drops/renames a column):
//   SELECT table_name, array_agg(column_name ORDER BY ordinal_position)
//   FROM information_schema.columns WHERE table_schema='public'
//   GROUP BY table_name;  -- against project dedsavbjuwgarrhphgnl
//   → write backups/live_schema_columns.json
//
// Usage: dart run scripts/check_schema_column_refs.dart

import 'dart:convert';
import 'dart:io';

void main() {
  final snapFile = File('backups/live_schema_columns.json');
  if (!snapFile.existsSync()) {
    stderr.writeln(
        '[schema-col-refs] FAIL: backups/live_schema_columns.json missing');
    exit(1);
  }
  final snap = jsonDecode(snapFile.readAsStringSync()) as Map<String, dynamic>;
  final tables = (snap['tables'] as Map<String, dynamic>).map(
      (t, cols) => MapEntry(t, (cols as List).map((c) => c as String).toSet()));
  final buckets =
      ((snap['storage_buckets'] as List?) ?? const []).map((b) => b as String).toSet();

  final libDir = Directory('lib');
  if (!libDir.existsSync()) {
    stderr.writeln('[schema-col-refs] FAIL: lib/ does not exist');
    exit(1);
  }

  // Filter methods whose FIRST positional arg is a column name.
  final filterMethods = {
    'eq', 'neq', 'gt', 'gte', 'lt', 'lte', 'like', 'ilike', 'order', 'contains'
  };

  final violations = <String>[];
  var refsChecked = 0;

  final dartFiles = libDir
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'));

  for (final file in dartFiles) {
    final rel = file.path.replaceAll('\\', '/');
    final src = file.readAsStringSync();

    // Find each `.from('<table>')`. For each, take the statement window up to
    // the next `;` and validate the chained column references inside it.
    for (final m in RegExp(r"""\.from\(\s*['"]([\w-]+)['"]\s*\)""").allMatches(src)) {
      final table = m.group(1)!;

      // Skip storage buckets — supabase.storage.from('bucket').
      if (buckets.contains(table)) continue;

      // Heuristic storage detection: `storage` token within 40 chars before.
      final preStart = (m.start - 40) < 0 ? 0 : m.start - 40;
      final pre = src.substring(preStart, m.start);
      if (pre.contains('storage')) continue;

      if (!tables.containsKey(table)) {
        final lineNo = '\n'.allMatches(src.substring(0, m.start)).length + 1;
        violations.add(
            "$rel:$lineNo  .from('$table') — table not in live schema snapshot "
            "(typo, or add it / mark as storage bucket)");
        continue;
      }
      final cols = tables[table]!;

      // Statement window: from the .from(...) to the next ';'.
      final semi = src.indexOf(';', m.end);
      final window = src.substring(m.end, semi == -1 ? src.length : semi);

      // --- select('a, b, c') ---
      for (final s in RegExp(r"""\.select\(\s*['"]([^'"]*)['"]""").allMatches(window)) {
        final arg = s.group(1)!.trim();
        if (arg.isEmpty || arg == '*') continue;
        // Skip embedded resource selects (contain a '(' — child(*) embedding).
        if (arg.contains('(')) continue;
        for (final rawCol in arg.split(',')) {
          final col = rawCol.trim();
          if (col.isEmpty || col == '*') continue;
          refsChecked++;
          if (!cols.contains(col)) {
            final lineNo =
                '\n'.allMatches(src.substring(0, m.start)).length + 1;
            violations.add(
                "$rel:$lineNo  $table.select '$col' — no such column on $table");
          }
        }
      }

      // --- filter/order methods: first string-literal arg is a column ---
      for (final method in filterMethods) {
        final re = RegExp("\\.$method\\(\\s*['\"]([\\w]+)['\"]");
        for (final f in re.allMatches(window)) {
          final col = f.group(1)!;
          refsChecked++;
          if (!cols.contains(col)) {
            final lineNo =
                '\n'.allMatches(src.substring(0, m.start)).length + 1;
            violations.add(
                "$rel:$lineNo  $table.$method('$col') — no such column on $table");
          }
        }
      }
    }
  }

  if (violations.isNotEmpty) {
    stderr.writeln(
        '[schema-col-refs] FAIL: ${violations.length} column reference(s) do '
        'not match backups/live_schema_columns.json:');
    for (final v in violations) {
      stderr.writeln('  - $v');
    }
    stderr.writeln('\nIf a column was legitimately added/renamed, regenerate '
        'the snapshot (see this script header) in the same commit as the '
        'migration.');
    exit(1);
  }

  stdout.writeln(
      '[schema-col-refs] OK: $refsChecked column references validated against '
      'live schema snapshot; 0 drift.');
}
