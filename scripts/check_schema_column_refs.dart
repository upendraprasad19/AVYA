// scripts/check_schema_column_refs.dart
//
// Gate — Supabase column-reference validation against the live schema.
//
// THE STRUCTURAL ANSWER to "why do bugs survive our audits?": every prior
// audit was static (code-read + mock-data unit tests + targeted schema
// queries). None cross-checked the *column string literals* in queries
// against the real Postgres catalog. That blind spot produced THREE wrong-
// column bugs in the 2026-05-30 web-E2E batch alone:
//   - e2a4f7  user_profile.full_name  (column lives on `users`)
//   - f4b2c9  rank_promotions.created_at + client_errors.message/severity (trigger)
//   - a7c3e1  daily_steps.total_steps + sleep_logs.hours (this gate's founding case)
// All three were the SAME class: a *plausible* column name that never matched
// the DDL, throwing 42703 at runtime and silently degrading.
//
// This gate extracts every PostgREST column reference and validates each
// <col> against backups/live_schema_columns.json for its <table>:
//   .from('<table>') ... .select('<cols>') / .eq('<col>', ) / .neq / .gt / .gte
//   / .lt / .lte / .like / .ilike / .order('<col>', ) / .contains('<col>', )
//
// SCAN SCOPE — BOTH sides of the client↔server seam (regression-prevention
// batch 2026-06-08, WI-1): the SAME PostgREST grammar is used by
// supabase_flutter (Dart, lib/) and supabase-js (TS, supabase/functions/).
// Before 2026-06-08 this gate scanned lib/ ONLY, so every server-side
// wrong-column bug (9e1d4c nonexistent table, b9f4d2 rank-cron columns,
// the f4b2c9 trigger class) was invisible BY CONSTRUCTION. Measured: 53% of
// recent fix-regressions were this cloud-contract class. Now scans:
//   - lib/**/*.dart            (client)
//   - supabase/functions/**/*.ts (Edge Functions — server)
//
// SCOPE / LIMITS (honest):
//   - Validates string-literal columns in select()/filter()/order() AND
//     insert()/update()/upsert() map-literal keys (single-line + first line of
//     multi-line maps; spreads and computed keys are skipped, not failed).
//   - select('*') / select() / embedded resource selects ('*, child(*)') skip
//     column validation (PostgREST resource embedding, not flat columns).
//   - supabase.storage.from('<bucket>') is skipped via the storage_buckets
//     allowlist in the snapshot + a `storage` proximity heuristic.
//   - .rpc('fn') and .from(<variable>) / .from(`template`) are NOT validated
//     (no string-literal table/columns to check) — partial coverage by design.
//   - Raw SQL inside Edge Functions / Postgres trigger bodies is NOT covered
//     here; that is the separate migration-SQL lint (WI-1 part ii) +
//     trigger-smoke test (WI-1 part iii).
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

/// Methods whose FIRST positional arg is a column name.
const _filterMethods = {
  'eq', 'neq', 'gt', 'gte', 'lt', 'lte', 'like', 'ilike', 'order', 'contains'
};

/// Write-methods whose argument is a map literal of column keys.
const _writeMethods = {'insert', 'update', 'upsert'};

/// supabase-js keys that appear in a method's OPTIONS object (2nd arg), not in
/// the values map — never columns. Excluded so `.upsert({...}, {onConflict})`
/// doesn't false-flag `onConflict` as a column.
const _writeOptionKeys = {
  'onConflict', 'ignoreDuplicates', 'count', 'head', 'returning',
  'defaultToNull', 'ascending', 'nullsFirst', 'foreignTable', 'referencedTable'
};

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
  final buckets = ((snap['storage_buckets'] as List?) ?? const [])
      .map((b) => b as String)
      .toSet();

  final violations = <String>[];
  var refsChecked = 0;

  // --- Source set: client (lib/*.dart) + server (supabase/functions/**/*.ts) ---
  final sources = <File>[];

  final libDir = Directory('lib');
  if (!libDir.existsSync()) {
    stderr.writeln('[schema-col-refs] FAIL: lib/ does not exist');
    exit(1);
  }
  sources.addAll(libDir
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart')));

  final fnDir = Directory('supabase/functions');
  if (fnDir.existsSync()) {
    sources.addAll(fnDir
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.ts')));
  }

  for (final file in sources) {
    final rel = file.path.replaceAll('\\', '/');
    final src = file.readAsStringSync();
    refsChecked += _scanSource(rel, src, tables, buckets, violations);
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
        'migration. For Edge Functions, also confirm the table/column exists '
        'on project dedsavbjuwgarrhphgnl.');
    exit(1);
  }

  stdout.writeln(
      '[schema-col-refs] OK: $refsChecked column references validated against '
      'live schema snapshot (lib/ + supabase/functions/); 0 drift.');
}

/// Scans one source file (Dart or TS — identical PostgREST grammar) and appends
/// any column-reference violations. Returns the number of refs checked.
int _scanSource(String rel, String src, Map<String, Set<String>> tables,
    Set<String> buckets, List<String> violations) {
  var refsChecked = 0;

  int lineOf(int offset) =>
      '\n'.allMatches(src.substring(0, offset)).length + 1;

  for (final m
      in RegExp(r"""\.from\(\s*['"]([\w-]+)['"]\s*\)""").allMatches(src)) {
    final table = m.group(1)!;

    // Skip storage buckets — supabase.storage.from('bucket').
    if (buckets.contains(table)) continue;
    final preStart = (m.start - 40) < 0 ? 0 : m.start - 40;
    if (src.substring(preStart, m.start).contains('storage')) continue;

    if (!tables.containsKey(table)) {
      violations.add(
          "$rel:${lineOf(m.start)}  .from('$table') — table not in live schema "
          "snapshot (typo, or add it / mark as storage bucket)");
      continue;
    }
    final cols = tables[table]!;

    // Statement window: from the .from(...) to the next ';' OR the next
    // `.from(` (whichever comes first), so one query's chain never bleeds into
    // the next — important for TS files where multiple queries can share a
    // semicolon-light region.
    final semi = src.indexOf(';', m.end);
    final nextFrom = src.indexOf('.from(', m.end);
    var end = semi == -1 ? src.length : semi;
    if (nextFrom != -1 && nextFrom < end) end = nextFrom;
    final window = src.substring(m.end, end);

    // --- select('a, b, c') ---
    for (final s
        in RegExp(r"""\.select\(\s*['"]([^'"]*)['"]""").allMatches(window)) {
      final arg = s.group(1)!.trim();
      if (arg.isEmpty || arg == '*') continue;
      if (arg.contains('(')) continue; // embedded resource select
      for (final rawCol in arg.split(',')) {
        final col = rawCol.trim();
        if (col.isEmpty || col == '*') continue;
        refsChecked++;
        if (!cols.contains(col)) {
          violations
              .add("$rel:${lineOf(m.start)}  $table.select '$col' — no such "
                  "column on $table");
        }
      }
    }

    // --- filter/order methods: first string-literal arg is a column ---
    for (final method in _filterMethods) {
      for (final f
          in RegExp("\\.$method\\(\\s*['\"]([\\w]+)['\"]").allMatches(window)) {
        final col = f.group(1)!;
        refsChecked++;
        if (!cols.contains(col)) {
          violations.add("$rel:${lineOf(m.start)}  $table.$method('$col') — no "
              "such column on $table");
        }
      }
    }

    // --- write methods: insert/update/upsert map-literal keys ---
    // Conservative: only validate quoted/bare keys on the SAME line as the
    // method call's opening brace (single-line maps + the first line of a
    // multi-line map). Spreads (...x) and computed keys ([k]) are skipped, not
    // failed, to avoid false positives the gate header warns about.
    for (final method in _writeMethods) {
      for (final w in RegExp("\\.$method\\(\\s*\\{").allMatches(window)) {
        // Key region: from the opening brace to the FIRST of its closing '}'
        // or end-of-line. Bounding at '}' excludes a trailing options object on
        // the same line (`.upsert({...}, {onConflict})`); bounding at EOL keeps
        // multi-line maps to their first line (documented partial coverage).
        final braceAt = w.end - 1;
        final close = window.indexOf('}', braceAt);
        final eol = window.indexOf('\n', braceAt);
        var keyEnd = window.length;
        if (close != -1) keyEnd = close;
        if (eol != -1 && eol < keyEnd) keyEnd = eol;
        final keyRegion = window.substring(braceAt, keyEnd);
        // Match `key:` and `"key":` / `'key':` — JS/TS object keys.
        for (final k
            in RegExp(r"""(?:^|[\{,]\s*)(?:['"]([\w]+)['"]|([\w]+))\s*:""")
                .allMatches(keyRegion)) {
          final col = k.group(1) ?? k.group(2)!;
          if (_writeOptionKeys.contains(col)) continue;
          refsChecked++;
          if (!cols.contains(col)) {
            violations.add("$rel:${lineOf(m.start)}  $table.$method key '$col' "
                "— no such column on $table");
          }
        }
      }
    }
  }

  return refsChecked;
}
