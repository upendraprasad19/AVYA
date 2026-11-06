// Source-grep contract for migration 128 — the usage_counters ledger
// (OI-162 slice 1, diagnose d3a7f1).
//
// WHAT THIS PROVES AND WHAT IT DOES NOT. This file pins the SHAPE of an applied,
// immutable migration: that its protective clauses are still present in the
// source of record. It cannot prove runtime behaviour — the behavioural half is
// `test/edge_functions/usage_counters_rls_denies_client_test.dart` (runs in CI
// against live prod), plus the live post-apply checks recorded in the
// diagnose-doc. Same split, and the same reasoning, as
// `test/contracts/admin_metrics_functions_role_revoke_test.dart`, whose header
// says a unit test cannot reach the live catalog.
//
// Comments are stripped BEFORE matching so a commented-out clause can never
// satisfy an assertion (feedback_source_grep_strip_comments_first).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _migration = 'supabase/migrations/128_usage_counters.sql';

String _stripSqlComments(String sql) => sql
    .split('\n')
    .map((l) {
      final i = l.indexOf('--');
      return i >= 0 ? l.substring(0, i) : l;
    })
    .join('\n');

void main() {
  late String sql;

  setUpAll(() {
    final f = File(_migration);
    expect(f.existsSync(), isTrue,
        reason: '$_migration is missing. It is APPLIED and immutable — it must '
            'not be deleted or renamed.');
    sql = _stripSqlComments(f.readAsStringSync());
  });

  group('usage_counters — the table', () {
    test('user_id CASCADEs from users', () {
      expect(
          sql.contains(RegExp(
              r'user_id\s+uuid\s+NOT NULL\s+REFERENCES\s+public\.users\(id\)\s+ON DELETE CASCADE',
              caseSensitive: false)),
          isTrue,
          reason: 'delete-account/index.ts:440 deleteUser is the only deletion '
              'path and DPDP compliance relies on cascade. Without the FK, '
              'quota rows outlive deleted users.');
    });

    test('RLS is enabled and NO policy is created on this table', () {
      expect(
          sql.contains(RegExp(
              r'ALTER TABLE\s+public\.usage_counters\s+ENABLE ROW LEVEL SECURITY',
              caseSensitive: false)),
          isTrue,
          reason: 'RLS-with-no-policy IS the security boundary here.');
      expect(sql.toLowerCase().contains('create policy'), isFalse,
          reason: 'A policy on usage_counters would let a non-service_role '
              'caller write, which is exactly what consume_quota being '
              'SECURITY INVOKER relies on being impossible.');
    });
  });

  group('consume_quota — the contract', () {
    test('is SECURITY INVOKER and not DEFINER mode', () {
      expect(sql.contains(RegExp(r'SECURITY\s+INVOKER', caseSensitive: false)),
          isTrue);
      // Switching to DEFINER would (a) re-open the cross-account escalation
      // surface the INVOKER design removes and (b) escalate this migration's
      // blast radius to catastrophic via
      // scripts/blast_radius_content_rules_lib.dart.
      expect(sql.contains(RegExp(r'SECURITY\s+DEFINER', caseSensitive: false)),
          isFalse,
          reason: 'No DEFINER-mode function may live in this migration.');
    });

    test('p_limit = 0 returns the sentinel instead of granting one free use',
        () {
      expect(sql.contains(RegExp(r'IF\s+p_limit\s*=\s*0\s+THEN')), isTrue,
          reason: 'The INSERT arm is not limit-gated — only the ON CONFLICT '
              'branch is — so without this guard the first call with a limit '
              'of 0 returns 1 and grants a use that should never exist.');
    });

    test('the INSERT arm inserts 1, not the column default', () {
      expect(sql.contains(RegExp(r'VALUES\s*\(\s*p_user_id\s*,\s*p_quota_key\s*,\s*p_window_start\s*,\s*1\s*,')),
          isTrue,
          reason: 'The first call IS a consumption. Relying on DEFAULT 0 '
              'returns 0 for it, and `0 >= limit` is false for every positive '
              'limit — every quota would grant one extra unit.');
    });

    test('the ON CONFLICT update is guarded by the limit', () {
      expect(sql.contains(RegExp(r'WHERE\s+uc\.used\s*<\s*p_limit')), isTrue,
          reason: 'Without this the counter increments past the limit forever.');
    });

    test('null and negative arguments raise rather than silently proceeding', () {
      // B-pass finding 7: the p_limit=0 guard was pinned and its siblings were
      // not. Verified live that both raise P0001, but nothing held them in
      // place. A dropped null-check would let a NULL user_id reach the INSERT
      // and fail on the NOT NULL column — a confusing error far from the cause;
      // a dropped negative-check would make `used < -1` false forever, so the
      // quota would reject every call and read as "always exhausted".
      expect(
          sql.contains(RegExp(
              r'IF\s+p_user_id\s+IS NULL\s+OR\s+p_quota_key\s+IS NULL\s+OR\s+p_window_start\s+IS NULL\s+THEN')),
          isTrue,
          reason: 'the null-argument guard must stay');
      expect(
          sql.contains(
              RegExp(r'IF\s+p_limit\s+IS NULL\s+OR\s+p_limit\s*<\s*0\s+THEN')),
          isTrue,
          reason: 'the invalid-limit guard must stay');
      // ⚠ EACH guard is pinned SEPARATELY, and that is not pedantry. The first
      // version of this assertion was `contains(RAISE EXCEPTION 'consume_quota:)`
      // — and a mutation converting the null guard's RAISE to `RETURN -1` left
      // it GREEN, because the OTHER raise still matched. Membership is not
      // completeness: a `contains` over a pattern that occurs twice cannot
      // detect one of them disappearing.
      expect(sql.contains(RegExp(r"RAISE EXCEPTION\s+'consume_quota: null argument'")),
          isTrue,
          reason: 'the null guard must RAISE. If it returns a sentinel instead, '
              'a programming error at the call site becomes indistinguishable '
              'from an exhausted quota.');
      expect(
          sql.contains(
              RegExp(r"RAISE EXCEPTION\s+'consume_quota: invalid limit")),
          isTrue,
          reason: 'the invalid-limit guard must RAISE, for the same reason.');
    });

    test('an exhausted quota returns -1 rather than NULL', () {
      expect(sql.contains(RegExp(r'IF\s+NOT FOUND\s+OR\s+v_used\s+IS NULL\s+THEN')),
          isTrue);
      expect(sql.contains(RegExp(r'RETURN\s+-1\s*;')), isTrue,
          reason: 'A skipped DO UPDATE returns no row, leaving v_used NULL. '
              'NULL is the value that reads as "fine" at a call site — '
              '`null >= limit` is false, which fails OPEN. The sentinel must '
              'be produced here, once, not handled by five future callers.');
    });
  });

  group('retention — a two-sided predicate', () {
    test('deletes only WINDOWED rows older than the window', () {
      expect(sql.contains(RegExp(r'window_start\s*<\s*now\(\)\s*-\s*interval')),
          isTrue);
    });

    test('NEVER deletes lifetime rows', () {
      // The mirror. A bound with only one side is a half-finished thought:
      // dropping this conjunct deletes every lifetime entitlement and
      // reintroduces the exact bug this table exists to fix, inside the new
      // table.
      expect(sql.contains(RegExp(r"window_start\s*<>\s*'epoch'")), isTrue,
          reason: 'Without the epoch exclusion, retention wipes every lifetime '
              'quota — the free-image and weekly-report entitlements — which '
              'is precisely the resettable-quota bug in a new location.');
    });
  });

  group('naming — the two rejected column names stay rejected', () {
    test('uses quota_key and used', () {
      expect(sql.contains('quota_key'), isTrue);
      expect(sql.contains(RegExp(r'\bused\b')), isTrue);
    });

    test('does not reintroduce meter or count as column names', () {
      expect(sql.contains(RegExp(r'^\s*meter\s+text', multiLine: true)), isFalse,
          reason: '`Meter` already names the Ward widget family in '
              'docs/naming_conventions.md; reusing it invites confusion.');
      expect(sql.contains(RegExp(r'^\s*count\s+integer', multiLine: true)),
          isFalse,
          reason: '`count` shadows the aggregate inside plpgsql and reads '
              'poorly in `count >= p_limit`.');
    });
  });
}
