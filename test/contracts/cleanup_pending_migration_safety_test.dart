// test/contracts/cleanup_pending_migration_safety_test.dart
//
// APK Test #16.1 / Agent B (closes-diagnose: a17bc3) — source-grep
// contract pinning the safety bounds on migration 066
// (cleanup_pending_chat_duplicates).
//
// If a future commit tries to:
//   - widen the 30-day upper bound (could delete forensic data)
//   - remove the 5-minute lower bound (could clobber live placeholders)
//   - drop the GROUP BY (would delete ALL pending rows, not just dupes)
// …this test fails.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final repoRoot =
      Directory.current.path; // tests run from project root in CI.
  final migrationPath =
      '$repoRoot/supabase/migrations/066_cleanup_pending_chat_duplicates.sql';

  late String source;

  setUpAll(() {
    final f = File(migrationPath);
    if (!f.existsSync()) {
      throw StateError(
        'Migration 066 missing — expected at $migrationPath. '
        'If renamed, update this test too.',
      );
    }
    source = f.readAsStringSync();
  });

  test('uses 30-day upper bound (forensic preservation)', () {
    expect(source.contains("interval '30 days'"), isTrue,
        reason:
            'Migration must scope DELETE to last 30 days. Widening this '
            'bound risks deleting historical research data.');
  });

  test('uses 5-minute lower bound (live-request protection)', () {
    expect(source.contains("interval '5 minutes'"), isTrue,
        reason:
            'Migration must exclude rows newer than 5 minutes. Removing '
            'this guard could clobber a placeholder that ai-proxy just '
            'INSERTed for an in-flight Gemini call.');
  });

  test('groups by (user_id, user_message, channel)', () {
    // Use a regex that allows arbitrary whitespace between tokens so a
    // future reformat doesn't break the contract.
    final groupBy = RegExp(
      r'GROUP\s+BY\s+user_id\s*,\s*user_message\s*,\s*channel',
      caseSensitive: false,
    );
    expect(groupBy.hasMatch(source), isTrue,
        reason:
            'Migration must GROUP BY (user_id, user_message, channel). '
            'Dropping any of these would over-delete (e.g. losing all '
            'placeholders across users).');
  });

  test('preserves one survivor per group (NOT IN survivors)', () {
    expect(source.toLowerCase().contains('not in'), isTrue,
        reason:
            'Migration must keep ONE survivor per group via NOT IN — '
            'otherwise it deletes the legitimate first-write too.');
  });

  test('only touches model_used=pending rows', () {
    expect(source.contains("model_used = 'pending'"), isTrue,
        reason:
            'Migration must only DELETE rows with model_used=pending. '
            'Touching successful interactions would destroy chat history.');
  });

  test('only touches ai_coach_interactions table', () {
    // Negative check: no other table mentioned as a DELETE target.
    final deleteFromTables = RegExp(
      r'DELETE\s+FROM\s+(\w+)',
      caseSensitive: false,
    ).allMatches(source);
    for (final m in deleteFromTables) {
      expect(m.group(1), equals('ai_coach_interactions'),
          reason: 'Unexpected DELETE FROM ${m.group(1)} in cleanup migration');
    }
  });

  test('wrapped in a transaction', () {
    final lower = source.toLowerCase();
    expect(lower.contains('begin;'), isTrue,
        reason: 'BEGIN; opens the transaction');
    expect(lower.contains('commit;'), isTrue,
        reason: 'COMMIT; closes the transaction');
  });

  test('references diagnose-doc id in header', () {
    expect(source.contains('a17bc3'), isTrue,
        reason: 'Migration must reference closes-diagnose: a17bc3');
  });
}
