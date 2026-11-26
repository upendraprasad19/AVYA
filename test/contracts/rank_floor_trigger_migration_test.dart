// Diagnose 8b1f3d: migration 184 recreates trg_dispatch_proactive_coach_promotion
// with WHEN (NEW.rank_code <> '<floor>'). PRESENCE-ONLY pins (the SQL runs only
// against the live database; behaviour is proven by
// test/sql/rank_floor_trigger_live_verify.sql): the floor literal equals the
// Dart and TS ladders' first rung, the migration rewrites no function, and its
// text never matches the blast-radius content rule that would escalate it
// (scripts/blast_radius_content_rules_lib.dart `containsSecurityDefiner`).
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/rank_ladder_data.dart';

import '../../scripts/blast_radius_content_rules_lib.dart';

const _migrationPath = 'supabase/migrations/184_rank_floor_trigger_when.sql';

String _sqlNoComments(String s) => s
    .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
    .replaceAll(RegExp(r'--[^\n]*'), '');

void main() {
  final raw = File(_migrationPath).readAsStringSync();
  final sql = _sqlNoComments(raw);

  test('the trigger is recreated with a WHEN clause naming the floor rung', () {
    final m = RegExp(
      r"CREATE\s+TRIGGER\s+trg_dispatch_proactive_coach_promotion\s+"
      r"AFTER\s+INSERT\s+ON\s+public\.rank_promotions\s+FOR\s+EACH\s+ROW\s+"
      r"WHEN\s*\(\s*NEW\.rank_code\s*<>\s*'([^']+)'\s*\)\s+"
      r"EXECUTE\s+FUNCTION\s+private\.dispatch_proactive_coach_promotion\(\)",
      caseSensitive: false,
    ).firstMatch(sql);
    expect(m, isNotNull, reason: 'CREATE TRIGGER ... WHEN (...) missing');
    final sqlFloor = m!.group(1);

    final ts = File('supabase/functions/_shared/rank_engine.ts')
        .readAsStringSync();
    final tsFloor = RegExp(
      r"export const kRankLadder[^=]*=\s*\[\s*\{\s*code:\s*'([^']+)'",
    ).firstMatch(ts)?.group(1);

    expect(sqlFloor, kRankLadder.first.code, reason: 'SQL vs Dart floor');
    expect(tsFloor, kRankLadder.first.code, reason: 'TS vs Dart floor');
  });

  test('the old binding is dropped first, in one transaction', () {
    final drop = sql.indexOf(RegExp(
        r'DROP\s+TRIGGER\s+IF\s+EXISTS\s+trg_dispatch_proactive_coach_promotion\s+ON\s+public\.rank_promotions',
        caseSensitive: false));
    final create = sql.indexOf(RegExp(r'CREATE\s+TRIGGER', caseSensitive: false));
    final begin = sql.indexOf(RegExp(r'^\s*BEGIN\s*;', multiLine: true));
    final commit = sql.indexOf(RegExp(r'^\s*COMMIT\s*;', multiLine: true));
    expect(begin, greaterThan(-1));
    expect(begin < drop && drop < create && create < commit, isTrue);
  });

  test('no function is created or replaced (the dispatch function is untouched)',
      () {
    expect(
        RegExp(r'CREATE\s+(OR\s+REPLACE\s+)?FUNCTION', caseSensitive: false)
            .hasMatch(sql),
        isFalse);
    expect(RegExp(r'ALTER\s+FUNCTION', caseSensitive: false).hasMatch(sql),
        isFalse);
  });

  test('the file text (comments included) does not escalate to catastrophic',
      () {
    expect(containsSecurityDefiner(raw), isFalse);
  });
}
