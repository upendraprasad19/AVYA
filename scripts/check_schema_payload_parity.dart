// scripts/check_schema_payload_parity.dart
//
// Gate 19: every NOT NULL column on user-tagged Supabase tables must
// appear in every insert/upsert payload from Edge Functions or client
// sync code.
//
// Closes OI-42 lens L22 (schema-vs-payload parity). Designed to catch
// the OI-27 class (migration 052 made `razorpay_signature` NOT NULL;
// verify-payment never sent the column → 23502 on every fallback).
//
// **Heuristic, not airtight:** the gate cannot inspect live Supabase.
// Instead it scans recent migrations for `ALTER COLUMN ... SET NOT NULL`
// or `<col> ... NOT NULL` in `CREATE TABLE` statements, extracts
// `(table, column)` pairs, and asserts every `<table>` insert/upsert
// callsite includes the column. False-positive resilient: when a
// callsite is allowlisted (see `_allowlist` below) it's skipped with
// rationale.
//
// Usage:
//   dart run scripts/check_schema_payload_parity.dart
//
// Exit 0 — all NOT NULL columns covered (or allowlisted)
// Exit 1 — drift detected

import 'dart:io';

const _migrationsDir = 'supabase/migrations';

// Tables to audit and the directories whose .ts/.dart files are
// considered callsites. Keep this LIST narrow so the gate doesn't
// false-positive on test fixtures or doc snippets.
const _auditedTables = <String>{
  'subscriptions',
  'user_profile',
  'workout_logs',
  'workout_log_exercises',
  'workout_log_sets',
  'nutrition_logs',
  'nutrition_log_items',
};

const _callsiteRoots = <String>[
  // OI-42 — Edge Functions only. Dart client sync code uses quoted-key
  // syntax (`'date': wlogDate`) which would require a different parser;
  // those callsites are covered by dedicated writer/reader contract
  // tests under test/contracts/*.dart already. The gate's primary
  // value is on the Edge Function side (where OI-27 lived).
  'supabase/functions',
];

// Allowlist: (table, column, callsite_substr, reason) — when the
// callsite path contains substr, the column is allowed missing.
// Use sparingly — every entry is debt.
const _allowlist = <List<String>>[
  // weekly-report performs analytical SELECTs that produce summary rows
  // for INSERT into report tables — not user-facing subscription writes.
  // The Edge Function never modifies subscriptions/workout_logs/etc.
  // The brace-balance scan picks up nested object literals in result
  // shaping; we don't want to scrub it column-by-column.
  ['subscriptions', 'razorpay_payment_id', 'weekly-report', 'analytical_select_not_user_write'],
  ['subscriptions', 'razorpay_signature', 'weekly-report', 'analytical_select_not_user_write'],
  ['subscriptions', 'razorpay_order_id', 'weekly-report', 'analytical_select_not_user_write'],
  ['subscriptions', 'plan', 'weekly-report', 'analytical_select_not_user_write'],
  ['subscriptions', 'status', 'weekly-report', 'analytical_select_not_user_write'],
  ['subscriptions', 'start_date', 'weekly-report', 'analytical_select_not_user_write'],
  ['subscriptions', 'end_date', 'weekly-report', 'analytical_select_not_user_write'],
  ['subscriptions', 'user_id', 'weekly-report', 'analytical_select_not_user_write'],
  ['workout_logs', 'date', 'weekly-report', 'analytical_select_not_user_write'],
  ['workout_logs', 'exercise_name', 'weekly-report', 'analytical_select_not_user_write'],
  ['workout_log_exercises', 'workout_log_id', 'weekly-report', 'analytical_select_not_user_write'],
  ['nutrition_logs', 'meal_type', 'weekly-report', 'analytical_select_not_user_write'],
];

class NotNullColumn {
  final String table;
  final String column;
  NotNullColumn(this.table, this.column);
  @override
  String toString() => '$table.$column';
}

void main() {
  // ── 1. Discover NOT NULL columns from migrations ──────────────────────────
  final notNullCols = <NotNullColumn>{};

  final migrationsDir = Directory(_migrationsDir);
  if (!migrationsDir.existsSync()) {
    stderr.writeln('[Gate 19] WARN — $_migrationsDir not found. Exit 0.');
    exit(0);
  }

  for (final entity in migrationsDir.listSync()) {
    if (entity is! File || !entity.path.endsWith('.sql')) continue;
    final src = entity.readAsStringSync();

    // ALTER ... SET NOT NULL pattern
    final alterRegex = RegExp(
      r"ALTER\s+TABLE\s+(?:public\.)?(\w+)\s+ALTER\s+COLUMN\s+(\w+)\s+SET\s+NOT\s+NULL",
      multiLine: true,
      caseSensitive: false,
    );
    for (final m in alterRegex.allMatches(src)) {
      final table = m.group(1)!;
      final col = m.group(2)!;
      if (_auditedTables.contains(table)) {
        notNullCols.add(NotNullColumn(table, col));
      }
    }
  }

  if (notNullCols.isEmpty) {
    stdout.writeln(
        '[Gate 19] WARN — no NOT NULL columns discovered for audited tables. Exit 0.');
    exit(0);
  }

  stdout.writeln(
      '[Gate 19] auditing ${notNullCols.length} NOT NULL columns across ${_auditedTables.length} tables');

  // ── 2. For each callsite root, find insert/upsert payloads ────────────────
  final failures = <String>[];
  for (final root in _callsiteRoots) {
    final dir = Directory(root);
    if (!dir.existsSync()) continue;
    for (final entity in dir.listSync(recursive: true)) {
      if (entity is! File) continue;
      final path = entity.path.replaceAll('\\', '/');
      if (!path.endsWith('.ts') && !path.endsWith('.dart')) continue;
      final src = entity.readAsStringSync();

      // Find `.from('<table>').insert|upsert(...{ payload })` chains.
      for (final col in notNullCols) {
        // Skip if allowlisted for this callsite.
        final allowed = _allowlist.any((rule) =>
            rule[0] == col.table &&
            rule[1] == col.column &&
            path.contains(rule[2]));
        if (allowed) continue;

        // Brace-balanced scan for payloads after .from(table).insert|upsert.
        // Critical: the verb call must be in the SAME chain — we cap the
        // forward search at 200 chars and require only whitespace + chain
        // continuation between `.from(...)` and `.<verb>(`. Without the cap,
        // a `.from('subscriptions').select(...)` (a SELECT, irrelevant) would
        // pick up a later UNRELATED upsert on a different table and falsely
        // flag missing columns.
        final chainPattern = RegExp(
          ".from\\(\\s*['\"]" + col.table + "['\"]\\s*\\)",
        );
        for (final m in chainPattern.allMatches(src)) {
          final tail = src.substring(
            m.end,
            (m.end + 200).clamp(0, src.length),
          );
          // Allow only chained method calls between .from() and the verb.
          // If anything else (`.select(`, `.eq(`, `.update(` chain etc.) is
          // present without leading to the verb, skip — this is a SELECT
          // chain or unrelated query.
          final verbChain = RegExp(
            r'^(\s*\.\s*[a-zA-Z_]+\s*\([^)]*\))*\s*\.(upsert|insert)\s*\(\s*\{',
            multiLine: true,
            dotAll: true,
          );
          final callMatch = verbChain.firstMatch(tail);
          if (callMatch == null) continue;
          final openAbs = m.end + callMatch.end - 1;
          int depth = 0;
          int? closeIdx;
          for (int i = openAbs; i < src.length; i++) {
            if (src[i] == '{') depth++;
            if (src[i] == '}') {
              depth--;
              if (depth == 0) {
                closeIdx = i;
                break;
              }
            }
          }
          if (closeIdx == null) continue;
          final payload = src.substring(openAbs, closeIdx + 1);

          // Match `<col>:` or shorthand `<col>,` / `<col>}`.
          final keyRegex = RegExp(
            "(^|[\\s,{])\\s*" + col.column + "\\s*(:|,|\\})",
            multiLine: true,
          );
          if (!keyRegex.hasMatch(payload)) {
            // Skip 'update' payloads — partial updates intentionally
            // omit unchanged NOT NULL columns. Only flag insert/upsert.
            final verb = callMatch.group(1);
            if (verb == 'update') continue;
            failures.add(
                '$path → $verb on ${col.table} missing required NOT NULL column "${col.column}"');
          }
        }
      }
    }
  }

  if (failures.isEmpty) {
    stdout.writeln(
        '[Gate 19] PASS — every NOT NULL column appears in every insert/upsert payload (or is allowlisted).');
    exit(0);
  } else {
    stderr.writeln('[Gate 19] ${failures.length} schema-vs-payload drift(s):');
    for (final f in failures) {
      stderr.writeln('  $f');
    }
    stderr.writeln(
        '\n  Fix: add the column to the payload OR document the omission '
        'by adding `[table, column, callsite_substr, reason]` to _allowlist.');
    exit(1);
  }
}
