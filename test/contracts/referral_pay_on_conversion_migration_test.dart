// test/contracts/referral_pay_on_conversion_migration_test.dart
//
// Migration 160 (hardening, the referrer_summary aggregate, the 90 percent promo ceiling) is pinned in group 6; the sections
// below keep pinning migration 159, whose text is APPLIED AND IMMUTABLE (its own DDL, ACL, cron job, rollback block and the
// helper it alone defines are read from the 159 file itself; the job and redeem bodies follow the highest-numbered migration
// that defines them, which is 160 and equals the 159 body plus exactly one stated change, group 6).
//
// Migration 159 - the REFERRER is rewarded when the friend PAYS (7 PRO days for a monthly payment, 30 for yearly, vested 7
// days after the payment); the friend still gets 7 days when the code is applied. Founder decision 2026-10-12. This file
// REPLACES test/contracts/referral_referrer_cap_migration_test.dart (migration 158's 7-per-90-days cap, withdrawn by the
// same decision); each group below is the named successor of one old group.
//
// WHAT THIS FILE IS, AND IS NOT. These are SOURCE pins on the migration text. They prove the rule is WRITTEN, in the
// definition that is LIVE (the highest-numbered migration defining each function: `CREATE OR REPLACE` makes a function's
// body the last one, CLAUDE.md 4.9). They cannot prove what the code DOES. That is:
//   * test/sql/referral_pay_on_conversion_live_verify.sql      (the cases against the real functions, one transaction; its SUMMARY line counts them)
//   * test/sql/referral_pay_on_conversion_deletion_replica.sql (account deletion; REPLICA ONLY)
//   * test/sql/referral_pay_on_conversion_concurrency_local.sh (two sessions; held locks; REPLICA ONLY)
// run on a local replica and under the SQL mutants of docs/plans/referral-pay-on-conversion.md section 3. They pin
// nothing about the Edge Function's new behaviour (unit S2 owns that) and nothing about the client counts surface (unit C).
//
// WHOLE STATEMENTS, not clauses. A per-clause contains() misses an AND/OR swap or a dropped predicate beside a kept one, so
// every load-bearing statement below is compared as ONE squashed string.
//
// Groups: live-definition; 1 THE RULE; 2 THE ORDER; 2b the three alerts; 3 WHAT DID NOT CHANGE (+ the DDL, the ACL, the cron
// job); 3b the inline rollback; 3c the credit statements; 3d the replica schema is one transaction; 3e the replica carries the
// live RLS shape; 4 writer<->reader (EF <-> RPC); 4b readers tolerate a NULL party; 4c the alert thresholds equal the yaml;
// 5 live schema; 6 migration 160.
//
// Run: flutter test test/contracts/referral_pay_on_conversion_migration_test.dart

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/migration_cap_reader.dart';

const _redeem = 'redeem_referral_atomic';
const _replicaSchemaPath = 'test/sql/referral_pay_on_conversion_replica_schema.sql';
const _m159Path = 'supabase/migrations/159_referral_reward_on_conversion.sql';
const _m160Path = 'supabase/migrations/160_referral_hardening.sql';

/// The block of `CREATE [OR REPLACE] FUNCTION <schema>.<name> ... $tag$ ... $tag$` in [sql], comment-stripped; null if absent.
String? schemaFunctionBlock(String sql, String schema, String name) {
  final body = stripSqlComments(sql);
  final start = RegExp('CREATE\\s+(?:OR\\s+REPLACE\\s+)?FUNCTION\\s+$schema\\.$name\\b').firstMatch(body);
  if (start == null) return null;
  final rest = body.substring(start.start);
  final tag = RegExp(r'\$([A-Za-z_][A-Za-z0-9_]*)?\$').firstMatch(rest);
  if (tag == null) return null;
  final delim = tag.group(0)!;
  final close = rest.indexOf(delim, tag.end);
  if (close < 0) return null;
  return rest.substring(0, close + delim.length);
}

/// The highest-numbered migration that defines `<schema>.<name>`.
File? latestMigrationDefiningIn(String schema, String name) {
  final defs = Directory('supabase/migrations')
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.sql'))
      .where((f) => schemaFunctionBlock(f.readAsStringSync(), schema, name) != null)
      .toList()
    ..sort((a, b) => migrationNumber(a.uri.pathSegments.last).compareTo(migrationNumber(b.uri.pathSegments.last)));
  return defs.isEmpty ? null : defs.last;
}

String squash(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim();

/// [sql] with every dollar-quoted region removed (what is left is the migration's own top-level statements).
String outsideDollarQuotes(String sql) => sql.replaceAll(RegExp(r'\$([A-Za-z_]\w*)?\$[\s\S]*?\$\1\$'), '');

void main() {
  final latest = latestMigrationDefining(_redeem);
  final liveSql = latest?.readAsStringSync() ?? '';
  final code = squash(stripSqlComments(liveSql));
  final redeemBody = squash(functionBlock(liveSql, _redeem) ?? '');
  final jobBody = squash(schemaFunctionBlock(liveSql, 'private', 'process_referral_conversions') ?? '');
  // The helper is defined by 159 alone; its pins follow whichever migration defines it last.
  final helperFile = latestMigrationDefiningIn('private', 'grant_referral_days');
  final helperBody = squash(schemaFunctionBlock(helperFile?.readAsStringSync() ?? '', 'private', 'grant_referral_days') ?? '');
  // Migration 159's own text (applied, immutable): DDL, ACL, cron job, rollback block.
  final sql159 = File(_m159Path).readAsStringSync();
  final code159 = squash(stripSqlComments(sql159));

  group('the live definition (the highest-numbered migration defining each function)', () {
    test('migration 160 (or a later one) is the live definition of the redeem RPC and the job; the helper is still 159\'s', () {
      expect(latest, isNotNull);
      expect(migrationNumber(latest!.uri.pathSegments.last), greaterThanOrEqualTo(160));
      expect(redeemBody, isNotEmpty);
      final job = latestMigrationDefiningIn('private', 'process_referral_conversions');
      expect(job, isNotNull, reason: 'private.process_referral_conversions must be defined by a migration');
      expect(job!.path, latest.path, reason: 'the job and $_redeem must be defined by the SAME (latest) migration');
      expect(helperFile, isNotNull, reason: 'private.grant_referral_days must be defined by a migration');
      expect(migrationNumber(helperFile!.uri.pathSegments.last), greaterThanOrEqualTo(159));
      expect(jobBody, isNotEmpty);
      expect(helperBody, isNotEmpty);
    });
  });

  group('1. the rule', () {
    test('the window is 90 days, the vest 7 days, the detection scan 97 days, declared as constants', () {
      expect(jobBody, contains("c_window CONSTANT interval := interval '90 days';"));
      expect(jobBody, contains("c_vest CONSTANT interval := interval '7 days';"));
      expect(jobBody, contains("c_scan CONSTANT interval := interval '97 days';"));
    });

    test('the reconcile: candidates, the earliest qualifying payment, the reward CASE and the guard are ONE statement', () {
      const expected = r"WITH cand AS MATERIALIZED ( SELECT rr.id, rr.referee_id, rr.created_at FROM referral_redemptions rr "
          r"WHERE rr.referrer_id IS NOT NULL AND rr.referrer_rewarded IS NOT TRUE "
          r"AND (rr.created_at > now() - c_scan OR rr.converted_at IS NOT NULL) FOR UPDATE OF rr SKIP LOCKED ), "
          r"calc AS ( SELECT c.id, q.start_date, q.plan FROM cand c LEFT JOIN LATERAL ( "
          r"SELECT s.start_date, s.plan FROM subscriptions s WHERE s.user_id = c.referee_id "
          r"AND s.plan IN ('monthly', 'yearly') AND s.razorpay_payment_id IS NOT NULL AND s.status = 'active' "
          r"AND s.cancelled_at IS NULL AND s.start_date >= c.created_at AND s.start_date <= c.created_at + c_window "
          r"ORDER BY s.start_date, s.id LIMIT 1 ) q ON true ), "
          r"upd AS ( UPDATE referral_redemptions rr SET converted_at = calc.start_date, "
          r"referrer_reward_days = CASE calc.plan WHEN 'yearly' THEN 30 WHEN 'monthly' THEN 7 END FROM calc "
          r"WHERE rr.id = calc.id AND (rr.converted_at IS DISTINCT FROM calc.start_date "
          r"OR rr.referrer_reward_days IS DISTINCT FROM (CASE calc.plan WHEN 'yearly' THEN 30 WHEN 'monthly' THEN 7 END)) "
          r"RETURNING rr.converted_at ) "
          r"SELECT count(*) FILTER (WHERE converted_at IS NOT NULL), count(*) FILTER (WHERE converted_at IS NULL) "
          r"INTO v_reconciled, v_voided FROM upd;";
      expect(jobBody, contains(expected),
          reason: 'any change to the candidate filter, the payment predicate (plan, payment id, status, cancelled_at, the two '
              'window edges, earliest-first order), the 7/30 mapping or the IS DISTINCT FROM guard changes who is rewarded');
    });

    test('the reward CASE maps yearly to 30 and monthly to 7 with NO ELSE, in both places it appears', () {
      final cases = RegExp(r'CASE calc\.plan [^;]*?END').allMatches(jobBody).map((m) => m.group(0)!).toList();
      expect(cases, hasLength(2), reason: 'the SET and the IS DISTINCT FROM guard');
      for (final c in cases) {
        expect(c, "CASE calc.plan WHEN 'yearly' THEN 30 WHEN 'monthly' THEN 7 END");
      }
    });

    test('the paid-plan list is the same everywhere it appears, and the flag is never read with a bare NOT', () {
      final lists = RegExp(r"plan IN \(([^)]*)\)").allMatches(code).map((m) => m.group(1)!).toList();
      expect(lists, hasLength(3), reason: 'the redeem refusal, the same refusal re-checked after each retry pause (160), and the reconcile lateral');
      for (final l in lists) {
        expect(l, "'monthly', 'yearly'");
      }
      final noQualifier = RegExp(r'(?<!IS )NOT (rr\.)?referrer_rewarded').allMatches(jobBody);
      // `referrer_rewarded = true` appears exactly once, in the credit UPDATE; every other test is `IS NOT TRUE` (counted below).
      expect(noQualifier, isEmpty,
          reason: 'referrer_rewarded is nullable: `NOT referrer_rewarded` is NULL for a NULL row and hides it');
      expect('referrer_rewarded IS NOT TRUE'.allMatches(jobBody).length, 4, reason: 'stall watch, reconcile, credit select, credit update');
    });

    test('the credit selects only pending rows that have stood the vest, oldest first, with a referrer AND a referee (160)', () {
      expect(
          jobBody,
          contains(r'FOR r IN SELECT rr.id, rr.referrer_id, rr.referrer_reward_days AS reward_days FROM referral_redemptions rr '
              r'WHERE rr.converted_at IS NOT NULL AND rr.converted_at <= now() - c_vest AND rr.referrer_id IS NOT NULL '
              r'AND rr.referee_id IS NOT NULL AND rr.referrer_rewarded IS NOT TRUE ORDER BY rr.converted_at, rr.id LIMIT c_batch FOR UPDATE OF rr SKIP LOCKED LOOP'));
      expect(jobBody, contains('c_batch CONSTANT integer := 50;'),
          reason: 'a run credits at most 50: each sub-block takes a subtransaction id and every lock lives to the end of the run');
    });

    test('the redeem function credits ONLY the referee: no UPDATE, no referrer flag, one grant to the referee', () {
      expect(redeemBody, isNot(contains('UPDATE')));
      expect(redeemBody, isNot(contains('v_credit_referrer')));
      expect(redeemBody, isNot(contains('referrer_rewarded = true')));
      expect('private.grant_referral_days('.allMatches(redeemBody).length, 1);
      expect(redeemBody, contains('PERFORM private.grant_referral_days(p_referee_id, p_days);'));
      expect(
          redeemBody,
          contains('INSERT INTO referral_redemptions ( code, referrer_id, referee_id, days_granted_each, referrer_rewarded, '
              'referee_rewarded ) VALUES ( p_code, p_referrer_id, p_referee_id, p_days, false, true );'),
          reason: 'the audit row records the referrer as NOT yet rewarded and the referee as rewarded');
    });

    test('the redeem function refuses a referee who has EVER paid (any status), with the message the Edge Function maps', () {
      expect(
          redeemBody,
          contains("IF EXISTS ( SELECT 1 FROM subscriptions WHERE user_id = p_referee_id AND plan IN ('monthly', 'yearly') "
              "AND razorpay_payment_id IS NOT NULL ) THEN RAISE EXCEPTION 'referee_has_paid_plan' USING ERRCODE = 'P0001'; END IF;"));
    });

    test('there is no cap left: none of the 158 constants or counts survives in the executable SQL', () {
      for (final gone in <String>['c_referrer_cap', 'c_cap_window', 'v_credited_in_window', 'v_credit_referrer', 'v_key_referrer']) {
        expect(code, isNot(contains(gone)), reason: '$gone belonged to the withdrawn per-referrer cap');
      }
    });
  });

  group('2. the order', () {
    test('redeem: NULL guard, then ONE blocking lock on the REFEREE, then the paid refusal, the audit row, the grant', () {
      final g = redeemBody.indexOf("RAISE EXCEPTION 'redeem_referral_atomic: referrer and referee are required' USING ERRCODE = '23502';");
      final lock = redeemBody.indexOf('PERFORM pg_advisory_xact_lock(v_key_referee);');
      final pre = redeemBody.indexOf("RAISE EXCEPTION 'referee_has_paid_plan'");
      final ins = redeemBody.indexOf('INSERT INTO referral_redemptions');
      final grant = redeemBody.indexOf('PERFORM private.grant_referral_days(p_referee_id, p_days);');
      expect(g, greaterThanOrEqualTo(0));
      // The RAISE alone is not the guard: its CONDITION is (a `IF false THEN` would keep the statement and kill the check).
      expect(
          redeemBody,
          contains("BEGIN IF p_referrer_id IS NULL OR p_referee_id IS NULL THEN "
              "RAISE EXCEPTION 'redeem_referral_atomic: referrer and referee are required' USING ERRCODE = '23502'; END IF;"),
          reason: 'a NULL party must be refused with 23502 before anything is locked or written');
      expect(lock, greaterThan(g));
      expect(pre, greaterThan(lock), reason: 'the paid check runs inside the section the per-referee lock serialises, so two concurrent redemptions of one referee evaluate it one after the other');
      expect(ins, greaterThan(pre));
      expect(grant, greaterThan(ins));
      expect('pg_advisory_xact_lock('.allMatches(redeemBody).length, 1, reason: 'one lock: a second would be a new ordering to prove');
      expect(redeemBody, contains("v_key_referee bigint := hashtextextended('redeem_referral_atomic:' || p_referee_id::text, 0);"));
    });

    test('job: the stall watch, THEN the job try-lock, then reconcile, then the credit loop, then the alerts', () {
      final stall = jobBody.indexOf("'referral_conversions_stalled'");
      final lock = jobBody.indexOf("IF NOT pg_try_advisory_xact_lock(hashtextextended('process_referral_conversions', 0)) THEN "
          "RETURN jsonb_build_object('skipped', 'locked'); END IF;");
      final recon = jobBody.indexOf('WITH cand AS MATERIALIZED');
      final loop = jobBody.indexOf('FOR r IN SELECT');
      final alertFailed = jobBody.indexOf("'referral_conversions_failed'");
      final alertVolume = jobBody.indexOf("'referral_conversions_volume'");
      expect(stall, greaterThanOrEqualTo(0));
      expect(lock, greaterThan(stall),
          reason: 'the stall watch must run BEFORE the job lock: a forgotten session holding the lock makes every run return at the lock, '
              'so a watch placed after it would never fire in exactly the case it exists for');
      expect(recon, greaterThan(lock));
      expect(loop, greaterThan(recon), reason: 'detect and void BEFORE crediting, so a payment cancelled earlier is never paid');
      expect(alertFailed, greaterThan(loop));
      expect(alertVolume, greaterThan(alertFailed));
    });

    test('credit sub-block: referrer try-lock, users key-share NOWAIT, grant, flag UPDATE, ROW_COUNT check, in that order', () {
      const block = r"BEGIN IF NOT pg_try_advisory_xact_lock(hashtextextended('redeem_referral_atomic:' || r.referrer_id::text, 0)) "
          r"THEN v_skipped := v_skipped + 1; CONTINUE; END IF; "
          r"PERFORM 1 FROM public.users u WHERE u.id = r.referrer_id FOR KEY SHARE NOWAIT; IF NOT FOUND THEN CONTINUE; END IF; "
          r"PERFORM private.grant_referral_days(r.referrer_id, r.reward_days); "
          r"UPDATE referral_redemptions SET referrer_rewarded = true, referrer_credited_at = now() "
          r"WHERE id = r.id AND referrer_rewarded IS NOT TRUE; GET DIAGNOSTICS v_n = ROW_COUNT; "
          r"IF v_n <> 1 THEN RAISE EXCEPTION 'referral reward flag matched % rows for redemption %', v_n, r.id; END IF; "
          r"v_credited := v_credited + 1; "
          r"EXCEPTION WHEN lock_not_available THEN v_skipped := v_skipped + 1; "
          r"WHEN OTHERS THEN v_failed := v_failed + 1; v_failed_ids := v_failed_ids || r.id::text; END; END LOOP;";
      expect(jobBody, contains(block),
          reason: 'the key share before any INSERT into subscriptions closes the measured job-vs-account-deletion deadlock; the '
              'ROW_COUNT check rolls the grant back with a flag that did not stick');
    });

    test('helper: bounds check, then the NOWAIT read of the latest ACTIVE row, then the insert-or-update by id', () {
      const expected = r"IF p_user_id IS NULL OR p_days IS NULL OR p_days < 1 OR p_days > 30 THEN "
          r"RAISE EXCEPTION 'grant_referral_days: a user and 1..30 days are required (got %, %)', p_user_id, p_days "
          r"USING ERRCODE = '22023'; END IF; "
          r"SELECT s.id, s.end_date INTO v_id, v_end FROM subscriptions s WHERE s.user_id = p_user_id AND s.status = 'active' "
          r"ORDER BY s.end_date DESC, s.id LIMIT 1 FOR UPDATE NOWAIT; "
          r"IF v_id IS NULL OR v_end < now() THEN "
          r"INSERT INTO subscriptions (user_id, plan, status, start_date, end_date) "
          r"VALUES (p_user_id, 'referral_trial', 'active', now(), now() + (p_days || ' days')::interval); "
          r"ELSE UPDATE subscriptions SET end_date = end_date + (p_days || ' days')::interval WHERE id = v_id; END IF;";
      expect(helperBody, contains(expected));
    });
  });

  group('2b. alerts: three sources, each in its own sub-block, each deduplicated on its OWN source', () {
    test('stalled alert: counts vested rewards pending more than 10 days, warn, own source, 23-hour dedup, written BEFORE the lock', () {
      const expected = r"BEGIN SELECT count(*) INTO v_stalled FROM referral_redemptions rr WHERE rr.converted_at IS NOT NULL "
          r"AND rr.converted_at <= now() - c_stall AND rr.referrer_id IS NOT NULL AND rr.referrer_rewarded IS NOT TRUE; "
          r"IF v_stalled > 0 THEN INSERT INTO public.alerts (source, severity, summary, context_json, suggested_action) "
          r"SELECT 'referral_conversions_stalled', 'warn', "
          r"format('%s referral reward(s) have been pending more than 3 days past their vest: the hourly job is not crediting them', v_stalled), "
          r"jsonb_build_object('stalled', v_stalled), "
          r"'Check that cron.job referral_conversions_hourly is active, look for a long-open session holding the job''s advisory lock or a referrer''s, and read the failed and skipped_locked counts of the runs.' "
          r"WHERE NOT EXISTS ( SELECT 1 FROM public.alerts x WHERE x.source = 'referral_conversions_stalled' AND x.acknowledged = false "
          r"AND x.severity = 'warn' AND x.detected_at > now() - interval '23 hours' ); "
          r"END IF; EXCEPTION WHEN OTHERS THEN NULL; END;";
      expect(jobBody, contains(expected));
      expect(jobBody, contains("c_stall CONSTANT interval := interval '10 days';"));
    });

    test('failed alert: written only when something failed, severity warn, names the redemption ids, 23-hour dedup', () {
      const expected = r"IF v_failed > 0 THEN BEGIN INSERT INTO public.alerts (source, severity, summary, context_json, suggested_action) "
          r"SELECT 'referral_conversions_failed', 'warn', "
          r"format('%s referral reward credit(s) failed in the last run; the referrer(s) were not rewarded yet', v_failed), "
          r"jsonb_build_object('failed', v_failed, 'redemption_ids', to_jsonb(v_failed_ids)), "
          r"'Read cron.job_run_details for referral_conversions_hourly and the named referral_redemptions rows; the rewards stay pending and are retried every hour.' "
          r"WHERE NOT EXISTS ( SELECT 1 FROM public.alerts x WHERE x.source = 'referral_conversions_failed' AND x.acknowledged = false "
          r"AND x.severity = 'warn' AND x.detected_at > now() - interval '23 hours' ); "
          r"EXCEPTION WHEN OTHERS THEN NULL; END; END IF;";
      expect(jobBody, contains(expected));
    });

    test('volume alert: strictly more than 10 credits in a run or more than 20 redemptions in 24 hours, own source, 23-hour dedup', () {
      const expected = r"BEGIN IF v_credited > c_volume_credits OR (SELECT count(*) FROM referral_redemptions "
          r"WHERE created_at > now() - interval '24 hours') > c_volume_redemptions THEN "
          r"INSERT INTO public.alerts (source, severity, summary, context_json, suggested_action) "
          r"SELECT 'referral_conversions_volume', 'warn', "
          r"'Unusual referral volume: many rewards credited in one run or many redemptions in 24 hours', "
          r"jsonb_build_object( 'credited_this_run', v_credited, "
          r"'redemptions_24h', (SELECT count(*) FROM referral_redemptions WHERE created_at > now() - interval '24 hours'), "
          r"'max_redemptions_24h_one_referrer', (SELECT coalesce(max(c), 0) FROM (SELECT count(*) AS c FROM referral_redemptions "
          r"WHERE created_at > now() - interval '24 hours' AND referrer_id IS NOT NULL GROUP BY referrer_id) t)), "
          r"'Look for one referrer with many redemptions and look at the friends'' payments before more rewards vest.' "
          r"WHERE NOT EXISTS ( SELECT 1 FROM public.alerts x WHERE x.source = 'referral_conversions_volume' AND x.acknowledged = false "
          r"AND x.severity = 'warn' AND x.detected_at > now() - interval '23 hours' ); "
          r"END IF; EXCEPTION WHEN OTHERS THEN NULL; END;";
      expect(jobBody, contains(expected));
      expect(jobBody, contains('c_volume_credits CONSTANT integer := 10;'));
      expect(jobBody, contains('c_volume_redemptions CONSTANT integer := 20;'));
    });
  });

  group('3. what did not change, and what did', () {
    test('signature, return type, security mode and search_path of the redeem function', () {
      expect(code, contains('public.redeem_referral_atomic( p_code text, p_referrer_id uuid, p_referee_id uuid, p_days integer )'));
      expect(code, contains("RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'"),
          reason: 'omitting SET search_path in a CREATE OR REPLACE silently undoes migration 053');
    });

    test('the two private functions are SECURITY DEFINER with a pinned search_path', () {
      expect(code159, contains("CREATE OR REPLACE FUNCTION private.grant_referral_days(p_user_id uuid, p_days integer) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'"));
      expect(code, contains("CREATE OR REPLACE FUNCTION private.process_referral_conversions() RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'"));
    });

    test('the ACL: the private functions are for nobody, the redeem RPC for service_role only', () {
      const acl = r'REVOKE ALL ON FUNCTION private.grant_referral_days(uuid, integer) FROM PUBLIC; '
          r'REVOKE ALL ON FUNCTION private.grant_referral_days(uuid, integer) FROM anon, authenticated; '
          r'REVOKE ALL ON FUNCTION private.process_referral_conversions() FROM PUBLIC; '
          r'REVOKE ALL ON FUNCTION private.process_referral_conversions() FROM anon, authenticated; '
          r'REVOKE EXECUTE ON FUNCTION public.redeem_referral_atomic(text, uuid, uuid, integer) FROM PUBLIC; '
          r'REVOKE EXECUTE ON FUNCTION public.redeem_referral_atomic(text, uuid, uuid, integer) FROM anon, authenticated; '
          r'GRANT EXECUTE ON FUNCTION public.redeem_referral_atomic(text, uuid, uuid, integer) TO service_role;';
      expect(code159, contains(acl));
      expect(RegExp(r'\bGRANT\b').allMatches(code159).length, 1, reason: 'service_role only: a second GRANT would widen an ACL');
    });

    test('the migration header carries the four tags, and says non-destructive (159 and 160)', () {
      for (final sql in <String>[sql159, liveSql]) {
        final head = sql.split('\n').take(6).join('\n');
        expect(head, contains('-- Intent:'));
        expect(head, contains('-- Destructive?: no'));
        expect(head, contains('-- Rollback strategy: inline'));
        expect(head, contains('-- Linked diagnose-doc:'));
      }
    });

    test('migration 159: the only DDL is two ALTER TABLE statements on referral_redemptions; no row is rewritten at apply time', () {
      final alters = RegExp(r'ALTER TABLE [^;]*;').allMatches(code159).map((m) => m.group(0)!).toList();
      expect(alters, <String>[
        'ALTER TABLE public.referral_redemptions ADD COLUMN IF NOT EXISTS converted_at timestamptz, '
            'ADD COLUMN IF NOT EXISTS referrer_reward_days integer, ADD COLUMN IF NOT EXISTS referrer_credited_at timestamptz;',
        'ALTER TABLE public.referral_redemptions DROP CONSTRAINT IF EXISTS referral_redemptions_reward_days_check, '
            'DROP CONSTRAINT IF EXISTS referral_redemptions_converted_coherent_check, '
            'ADD CONSTRAINT referral_redemptions_reward_days_check CHECK (referrer_reward_days IS NULL OR referrer_reward_days IN (7, 30)), '
            'ADD CONSTRAINT referral_redemptions_converted_coherent_check CHECK ((converted_at IS NULL) = (referrer_reward_days IS NULL));',
      ], reason: '`Destructive?: no` holds only while nothing else is altered; the DROP and the ADD of a CHECK are ONE statement');
      final top = outsideDollarQuotes(stripSqlComments(sql159)).toUpperCase();
      for (final banned in <String>['DROP TABLE', 'DROP COLUMN', 'DROP FUNCTION', 'DROP INDEX', 'TRUNCATE', 'DELETE FROM', 'UPDATE ', 'INSERT INTO']) {
        expect(top, isNot(contains(banned)), reason: '`Destructive?: no` would be false with this top-level statement: $banned');
      }
    });

    test('migration 159: the DDL is bounded by a lock_timeout, released before the functions are created', () {
      final setIdx = code159.indexOf("SET lock_timeout = '3s';");
      final firstAlter = code159.indexOf('ALTER TABLE ');
      final lastAlter = code159.lastIndexOf('ALTER TABLE ');
      final reset = code159.indexOf('RESET lock_timeout;');
      final firstFn = code159.indexOf('CREATE OR REPLACE FUNCTION');
      expect(setIdx, greaterThanOrEqualTo(0));
      expect(firstAlter, greaterThan(setIdx), reason: 'the timeout precedes the first lock-taking statement');
      expect(reset, greaterThan(lastAlter));
      expect(firstFn, greaterThan(reset), reason: 'the functions are not created under a 3-second lock budget');
    });

    test('the cron job (created by 159, untouched by 160): name, schedule, the call, and the unschedule BY JOBID before the schedule', () {
      expect(code, isNot(contains('cron.schedule')), reason: '160 must not touch the job');
      expect(code, isNot(contains('cron.unschedule')), reason: '160 must not touch the job');
      expect(
          code159,
          contains("SELECT cron.unschedule(jobid) FROM cron.job WHERE jobname = 'referral_conversions_hourly'; "
              "SELECT cron.schedule('referral_conversions_hourly', '41 * * * *', \$\$SELECT private.process_referral_conversions()\$\$);"),
          reason: 'Gate 31 reads a quoted-name unschedule as "this job is gone" (OI-193); minute 41 is the free minute');
      expect(RegExp(r"cron\.unschedule\(\s*'").hasMatch(code159), isFalse);
    });
  });

  group('3b. the inline rollback', () {
    // A commented block at the end of migration 159 restores the live (158) definition verbatim (rollbackLines() reads 159 by default;
    // group 6 pins the same property for 160, whose rollback restores the 159 bodies).
    List<String> rollbackLines([String? sql]) {
      final lines = (sql ?? sql159).split('\n');
      final start = lines.indexWhere((l) => l.startsWith('-- Rollback (inline;'));
      expect(start, greaterThanOrEqualTo(0));
      final out = <String>[];
      for (final l in lines.skip(start + 1)) {
        if (l.startsWith('--   ')) {
          final s = l.substring(5);
          if (s.startsWith('-- ')) continue; // an instruction comment, not part of the body being restored
          out.add(s);
        } else if (l == '--') {
          out.add('');
        }
      }
      return out;
    }

    const endMarker = '\n\$function\$;';

    test('migration 159: the function in the rollback block equals the 158 definition kept in the replica schema, byte for byte', () {
      final rb = rollbackLines().join('\n');
      final from = rb.indexOf('CREATE OR REPLACE FUNCTION public.redeem_referral_atomic');
      final to = rb.indexOf(endMarker, from);
      expect(from, greaterThanOrEqualTo(0));
      expect(to, greaterThan(from));
      final rollbackFn = rb.substring(from, to + endMarker.length);

      final schema = File(_replicaSchemaPath).readAsStringSync();
      final sFrom = schema.indexOf('CREATE OR REPLACE FUNCTION public.redeem_referral_atomic');
      final sTo = schema.indexOf(endMarker, sFrom);
      expect(sFrom, greaterThanOrEqualTo(0));
      expect(sTo, greaterThan(sFrom));
      expect(rollbackFn, schema.substring(sFrom, sTo + endMarker.length), reason: 'the rollback must restore the 158 body exactly');
    });

    test('migration 159: the rollback order: unschedule, drop the job function, restore 158, THEN drop the helper, then the CHECKs and columns', () {
      final rb = rollbackLines().join('\n');
      final unschedule = rb.indexOf('cron.unschedule(');
      final dropJob = rb.indexOf('DROP FUNCTION IF EXISTS private.process_referral_conversions();');
      final restore = rb.indexOf('CREATE OR REPLACE FUNCTION public.redeem_referral_atomic');
      final dropHelper = rb.indexOf('DROP FUNCTION IF EXISTS private.grant_referral_days(uuid, integer);');
      final dropChecks = rb.indexOf('ALTER TABLE public.referral_redemptions');
      expect(unschedule, greaterThanOrEqualTo(0));
      expect(dropJob, greaterThan(unschedule));
      expect(restore, greaterThan(dropJob));
      expect(dropHelper, greaterThan(restore), reason: 'the 159 redeem body calls the helper: restore 158 BEFORE the helper is dropped');
      expect(dropChecks, greaterThan(dropHelper));
      for (final col in <String>['converted_at', 'referrer_reward_days', 'referrer_credited_at']) {
        expect(rb, contains('DROP COLUMN IF EXISTS $col'));
      }
      expect(rb, contains('DROP CONSTRAINT IF EXISTS referral_redemptions_reward_days_check'));
      expect(rb, contains('DROP CONSTRAINT IF EXISTS referral_redemptions_converted_coherent_check'));
    });
  });

  group('3c. the grant statements are the helper\'s, called from exactly two places', () {
    test('the helper is called by the redeem function (referee) and by the credit loop (referrer), nowhere else', () {
      final all = RegExp(r'PERFORM private\.grant_referral_days\(([^)]*)\);').allMatches(code).map((m) => m.group(1)!).toList();
      expect(all, <String>['p_referee_id, p_days', 'r.referrer_id, r.reward_days']);
    });

    test('the helper writes subscriptions only by INSERT of a referral_trial row or UPDATE of end_date by id', () {
      expect('INSERT INTO subscriptions'.allMatches(helperBody).length, 1);
      expect('UPDATE subscriptions'.allMatches(helperBody).length, 1);
      expect(helperBody, isNot(contains('DELETE')));
      expect(helperBody, isNot(contains('MAX(end_date)')), reason: '158 compared end_date to a MAX read; the helper locks and updates the row by id');
    });
  });

  group('3d. the replica schema file is one transaction, refuses a non-empty target, marker last', () {
    final schemaCode = squash(stripSqlComments(File(_replicaSchemaPath).readAsStringSync()));

    test('BEGIN first, COMMIT last, exactly one of each', () {
      expect(schemaCode.startsWith('BEGIN; '), isTrue);
      expect(schemaCode.endsWith(' COMMIT;'), isTrue);
      expect('BEGIN;'.allMatches(schemaCode).length, 1);
      expect('COMMIT;'.allMatches(schemaCode).length, 1);
    });

    test('a guard refuses a target that already holds any of the replica objects', () {
      final g = schemaCode.indexOf('DO \$guard\$');
      expect(g, greaterThanOrEqualTo(0));
      expect(g, lessThan(schemaCode.indexOf('CREATE SCHEMA private;')), reason: 'the guard runs before anything is created');
      final guard = schemaCode.substring(g, schemaCode.indexOf('\$guard\$;', g));
      for (final probe in <String>[
        "to_regclass('public.users')",
        "to_regclass('public.referral_redemptions')",
        "to_regclass('public.subscriptions')",
        "to_regclass('public.alerts')",
        "to_regclass('public.promo_codes')",
        "to_regclass('public.rpoc_replica_marker')",
        "to_regnamespace('auth')",
        "to_regnamespace('cron')",
        "to_regnamespace('private')",
        "to_regprocedure('public.redeem_referral_atomic(text,uuid,uuid,integer)')",
      ]) {
        expect(guard, contains('$probe IS NOT NULL'), reason: 'the guard must probe $probe');
      }
      expect(guard, contains("RAISE EXCEPTION 'REFUSED"));
    });

    test('the marker is created LAST, after every other object and the fixture users', () {
      final marker = schemaCode.indexOf('CREATE TABLE public.rpoc_replica_marker');
      expect(marker, greaterThanOrEqualTo(0));
      expect(marker, greaterThan(schemaCode.indexOf('INSERT INTO public.users')));
      expect(marker, greaterThan(schemaCode.indexOf('GRANT EXECUTE ON FUNCTION public.redeem_referral_atomic')));
      expect(marker, greaterThan(schemaCode.indexOf('CREATE POLICY')));
      expect('CREATE TABLE '.allMatches(schemaCode.substring(marker + 1)).length, 0, reason: 'nothing is created after the marker');
    });
  });

  group('3e. the replica carries the live row-level-security shape', () {
    final schemaCode = squash(stripSqlComments(File(_replicaSchemaPath).readAsStringSync()));

    test('RLS is enabled on the table, with exactly one policy, a SELECT policy over both user columns', () {
      expect(schemaCode, contains('ALTER TABLE public.referral_redemptions ENABLE ROW LEVEL SECURITY;'));
      expect('CREATE POLICY'.allMatches(schemaCode).length, 2,
          reason: 'live has exactly one policy on referral_redemptions and one on subscriptions; a write policy would hide the hole the deletion file tests');
      expect(
          schemaCode,
          contains('ALTER TABLE public.subscriptions ENABLE ROW LEVEL SECURITY; '
              'CREATE POLICY subscriptions_select_own ON public.subscriptions FOR SELECT USING ((select auth.uid()) = user_id);'),
          reason: 'the paid row the reward reads must be unforgeable by a user, as it is live (verify case A9 checks the live catalog)');
      expect(
          schemaCode,
          contains('CREATE POLICY "Users can read own redemptions" ON public.referral_redemptions FOR SELECT '
              'USING (((select auth.uid()) = referrer_id) OR ((select auth.uid()) = referee_id));'));
    });

    test('anon and authenticated hold the live full table grants incl. MAINTAIN, relacl arwdDxtm (so RLS is the only barrier)', () {
      expect(
          schemaCode,
          contains('GRANT SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER, MAINTAIN ON public.referral_redemptions '
              'TO anon, authenticated, service_role;'));
    });
  });

  group('4. writer<->reader: the Edge Function and the RPC agree', () {
    test('the EF calls the RPC with exactly the declared parameter names', () {
      final ef = stripDartComments(File('supabase/functions/redeem-referral/index.ts').readAsStringSync());
      final call = RegExp(r'supabase\.rpc\("redeem_referral_atomic",\s*\{([^}]*)\}', dotAll: true).firstMatch(ef);
      expect(call, isNotNull);
      final keys = RegExp(r'(\w+)\s*:').allMatches(call!.group(1)!).map((m) => m.group(1)!).toList();
      expect(keys, <String>['p_code', 'p_referrer_id', 'p_referee_id', 'p_days']);
      final declared = RegExp(r'public\.redeem_referral_atomic\(\s*([^)]*)\)')
          .firstMatch(stripSqlComments(liveSql))!
          .group(1)!
          .split(',')
          .map((p) => p.trim().split(RegExp(r'\s+')).first)
          .toList();
      expect(declared, keys, reason: 'a renamed or added SQL parameter would 404 the RPC at runtime');
    });
  });

  group('4b. readers tolerate a NULL referrer_id / referee_id', () {
    test('no Dart code reads either column out of a row (the restore path stores rows raw)', () {
      final hits = <String>[];
      final read = RegExp(r"""\[\s*['"](referee_id|referrer_id)['"]\s*\]""");
      for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
        final lines = f.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          final t = lines[i].trim();
          if (t.startsWith('//')) continue;
          if (read.hasMatch(t)) hits.add('${f.path}:${i + 1}');
        }
      }
      expect(hits, isEmpty,
          reason: 'the column is NULL once that account is deleted (ON DELETE SET NULL); a reader that casts it to a '
              'non-null type would throw in the restore path');
    });

    test('no Edge Function reads either column off a row (only filters and selects name them)', () {
      final hits = <String>[];
      final prop = RegExp(r'\b[A-Za-z_][A-Za-z0-9_]*\??\.(referee_id|referrer_id)\b');
      final sub = RegExp(r"""\[\s*['"`](referee_id|referrer_id)['"`]\s*\]""");
      for (final f in Directory('supabase/functions').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.ts'))) {
        if (f.path.endsWith('_test.ts') || f.path.contains('/tests/') || f.path.contains('/__tests__/')) continue;
        final lines = stripDartComments(f.readAsStringSync()).split('\n');
        for (var i = 0; i < lines.length; i++) {
          if (prop.hasMatch(lines[i]) || sub.hasMatch(lines[i])) hits.add('${f.path}:${i + 1}');
        }
      }
      expect(hits, isEmpty, reason: 'an Edge Function must not dereference a referral_redemptions party column');
    });

    test('the restore path stores the fetched rows raw, with no per-field read', () {
      final src = stripDartComments(File('lib/core/services/sync/sync_restore_completeness.dart').readAsStringSync());
      final start = src.indexOf('Future<void> _restoreReferralRedemptions(');
      expect(start, greaterThanOrEqualTo(0));
      final fn = squash(src.substring(start, src.indexOf('} catch (e, st)', start)));
      expect(fn, contains("await _hive.userBox.put('referral_redemption_history', rows);"),
          reason: 'rows with a NULL party go to the box untouched');
      expect(RegExp(r'rows\s*\.\s*(map|where|cast|map<)|\bas String\b').hasMatch(fn), isFalse,
          reason: 'parsing a party column here would throw on a deleted account\'s NULL');
    });
  });

  group('4c. the documented alert thresholds equal the constants in the migration (no silent drift)', () {
    final yaml = File('alerts/_thresholds.yaml').readAsStringSync();
    String block(String name) {
      final start = yaml.indexOf('\n  $name:');
      expect(start, greaterThanOrEqualTo(0), reason: '$name must be documented in alerts/_thresholds.yaml');
      final next = yaml.indexOf(RegExp(r'\n  [a-z_]+:\n|\n# '), start + 1);
      return yaml.substring(start, next == -1 ? yaml.length : next);
    }

    test('volume thresholds: the yaml numbers are the migration constants, and it names the migration that DEFINED the alert (159)', () {
      final b = block('referral_conversions_volume');
      final credits = RegExp(r'credits_in_one_run_above:\s*(\d+)').firstMatch(b)!.group(1)!;
      final redemptions = RegExp(r'redemptions_in_24h_above:\s*(\d+)').firstMatch(b)!.group(1)!;
      expect(jobBody, contains('c_volume_credits CONSTANT integer := $credits;'));
      expect(jobBody, contains('c_volume_redemptions CONSTANT integer := $redemptions;'));
      expect(b, contains('defined_in_migration: "159_referral_reward_on_conversion.sql"'));
    });

    test('the stalled alert is documented with the migration constant and the same 23-hour dedup', () {
      final b = block('referral_conversions_stalled');
      final days = RegExp(r'pending_days_above:\s*(\d+)').firstMatch(b)!.group(1)!;
      expect(jobBody, contains("c_stall CONSTANT interval := interval '$days days';"));
      expect(b, contains('dedup_window_hours: 23'));
      expect(b, contains('defined_in_migration: "159_referral_reward_on_conversion.sql"'));
    });

    test('the failed-credit alert is documented with the same 23-hour dedup the migration uses', () {
      final b = block('referral_conversions_failed');
      expect(b, contains('dedup_window_hours: 23'));
      expect(jobBody, contains("x.detected_at > now() - interval '23 hours'"));
      expect(b, contains('defined_in_migration: "159_referral_reward_on_conversion.sql"'));
    });
  });

  group('5. live schema', () {
    Map<String, dynamic> tables() {
      final snap = jsonDecode(File('backups/live_schema_columns.json').readAsStringSync()) as Map<String, dynamic>;
      return snap['tables'] is Map<String, dynamic> ? snap['tables'] as Map<String, dynamic> : snap;
    }

    test('the columns the rule reads exist live, and `redeemed_at` does not', () {
      final cols = (tables()['referral_redemptions'] as List).cast<String>();
      expect(cols, containsAll(<String>['created_at', 'referrer_rewarded', 'referee_rewarded', 'referrer_id', 'referee_id']));
      expect(cols, isNot(contains('redeemed_at')),
          reason: 'migration 037 names an index idx_..._redeemed_at and database.md listed a column; the live table has only created_at');
      expect(stripSqlComments(liveSql), isNot(contains('redeemed_at')), reason: 'the executable SQL must read the column that exists');
    });

    test('the three columns migration 159 adds are in the live snapshot (regenerated in the commit that follows the live apply)', () {
      final cols = (tables()['referral_redemptions'] as List).cast<String>();
      expect(cols, containsAll(<String>['converted_at', 'referrer_reward_days', 'referrer_credited_at']));
    });

    test('no column of the table can carry a payment id (the SELECT policy shows a row to BOTH parties)', () {
      final cols = (tables()['referral_redemptions'] as List).cast<String>();
      expect(cols.where((c) => c.contains('payment') || c.contains('razorpay')), isEmpty);
      expect(stripSqlComments(liveSql), isNot(contains('ADD COLUMN IF NOT EXISTS razorpay')));
      expect(code, isNot(contains('payment_id TEXT')));
    });
  });

  group('6. migration 160 (hardening, the referrer_summary aggregate, the promo ceiling)', () {
    final sql160 = File(_m160Path).existsSync() ? File(_m160Path).readAsStringSync() : '';   // missing file: group 6 fails with a clear reason, groups 1-5 still load
    final code160 = squash(stripSqlComments(sql160));
    test('migration 160 is on the branch', () => expect(sql160, isNotEmpty, reason: '$_m160Path is missing'));
    final redeem159 = squash(functionBlock(sql159, _redeem) ?? '');
    final job159 = squash(schemaFunctionBlock(sql159, 'private', 'process_referral_conversions') ?? '');
    final summaryBody = squash(functionBlock(sql160, 'referrer_summary') ?? '');
    const hidden = <String>['converted_at', 'referrer_reward_days', 'referrer_credited_at', 'referrer_rewarded', 'referee_rewarded'];
    const granted = <String>['id', 'code', 'referrer_id', 'referee_id', 'days_granted_each', 'created_at'];

    test('the header: four tags, non-destructive, inline rollback, the two diagnose docs exist', () {
      final head = sql160.split('\n').take(5).join('\n');
      expect(head, contains('-- Intent:'));
      expect(head, contains('-- Destructive?: no'));
      expect(head, contains('-- Rollback strategy: inline'));
      expect(head, contains('-- Linked diagnose-doc: c5e9a3 (stale credit), f2d6b8 (redeem lock wait)'));
      for (final id in <String>['c5e9a3', 'f2d6b8']) {
        final hit = Directory('docs/diagnoses').listSync().whereType<File>().where((f) => f.path.endsWith('$id.md'));
        expect(hit, hasLength(1), reason: 'the header names diagnose $id, which must exist');
      }
    });

    test('the job body equals the 159 body plus EXACTLY the referee_id predicate in the credit select', () {
      const before = 'WHERE rr.converted_at IS NOT NULL AND rr.converted_at <= now() - c_vest AND rr.referrer_id IS NOT NULL '
          'AND rr.referrer_rewarded IS NOT TRUE ORDER BY rr.converted_at, rr.id';
      const after = 'WHERE rr.converted_at IS NOT NULL AND rr.converted_at <= now() - c_vest AND rr.referrer_id IS NOT NULL '
          'AND rr.referee_id IS NOT NULL AND rr.referrer_rewarded IS NOT TRUE ORDER BY rr.converted_at, rr.id';
      expect(job159, isNotEmpty);
      expect(job159.split(before), hasLength(2), reason: 'the 159 credit select is the anchor of this comparison');
      expect(jobBody, job159.replaceFirst(before, after),
          reason: 'N1 changes ONE line of the job; any other difference is an unreviewed change to a catastrophic function');
    });

    test('the redeem body equals the 159 body with the single grant call replaced by the bounded retry', () {
      const grant = 'PERFORM private.grant_referral_days(p_referee_id, p_days); END;';
      // the paid-plan refusal of the 159 body, re-validated after each pause (a payment can land while the redeem waits)
      const paidCheck = "IF EXISTS ( SELECT 1 FROM subscriptions WHERE user_id = p_referee_id AND plan IN ('monthly', 'yearly') "
          "AND razorpay_payment_id IS NOT NULL ) THEN RAISE EXCEPTION 'referee_has_paid_plan' USING ERRCODE = 'P0001'; END IF;";
      const retry = 'FOR v_attempt IN 1..3 LOOP BEGIN PERFORM private.grant_referral_days(p_referee_id, p_days); EXIT; '
          'EXCEPTION WHEN lock_not_available THEN IF v_attempt = 3 THEN RAISE; END IF; PERFORM pg_sleep(0.25); $paidCheck END; END LOOP; END;';
      expect(redeem159.split(grant), hasLength(2));
      expect(redeem159.split(paidCheck), hasLength(2), reason: 'the re-validation must be the SAME predicate as the 159 refusal');
      expect(redeemBody, redeem159.replaceFirst(grant, retry),
          reason: 'N3 wraps the grant in ONE retry loop (3 attempts, 0.25 s, lock_not_available only, the third failure re-raised, '
              'the paid-plan refusal re-checked after every pause)');
      expect(redeemBody, contains('EXCEPTION WHEN lock_not_available THEN'));
      expect(redeemBody, isNot(contains('WHEN OTHERS')), reason: 'a widened handler would retry every error (mutant c_when_others)');
    });

    test('the grants: ALL privileges revoked from PUBLIC, anon and authenticated, SELECT re-granted on exactly the six columns', () {
      expect(
          code160,
          contains('REVOKE ALL ON public.referral_redemptions FROM PUBLIC; REVOKE ALL ON public.referral_redemptions FROM anon, authenticated; '
              'GRANT SELECT (id, code, referrer_id, referee_id, days_granted_each, created_at) '
              'ON public.referral_redemptions TO authenticated;'));
      final cols = RegExp(r'GRANT SELECT \(([^)]*)\) ON public\.referral_redemptions TO authenticated;').firstMatch(code160)!
          .group(1)!.split(',').map((c) => c.trim()).toList();
      expect(cols, granted);
      for (final h in hidden) {
        expect(cols, isNot(contains(h)), reason: '$h is a payment-status column no client may read');
      }
      // exactly three GRANT statements in the whole file: the six columns, the summary to authenticated, the redeem RPC to service_role
      expect(RegExp(r'\bGRANT\b').allMatches(code160).length, 3);
      expect(RegExp(r'GRANT[^;]*\bTO\b[^;]*\b(anon|PUBLIC)\b').hasMatch(code160), isFalse, reason: 'nothing is ever granted to anon or PUBLIC');
    });

    test('referrer_summary: signature, security, search_path (pg_temp LAST), the guard, the aggregate, the exact result keys', () {
      expect(summaryBody, contains("CREATE OR REPLACE FUNCTION public.referrer_summary() RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public', 'pg_temp'"));
      expect(summaryBody, contains('v_uid uuid := auth.uid();'));
      expect(summaryBody, contains("IF v_uid IS NULL THEN RAISE EXCEPTION 'referrer_summary: not authenticated' USING ERRCODE = '28000'; END IF;"));
      expect(
          summaryBody,
          contains('SELECT count(*), count(*) FILTER (WHERE rr.converted_at IS NOT NULL), count(*) FILTER (WHERE rr.referrer_rewarded IS TRUE), '
              'count(*) FILTER (WHERE rr.converted_at IS NOT NULL AND rr.referrer_rewarded IS NOT TRUE), '
              'coalesce(sum(CASE WHEN rr.referrer_rewarded IS TRUE THEN coalesce(rr.referrer_reward_days, rr.days_granted_each) END), 0) '
              'INTO v_joined, v_subscribed, v_credited, v_pending, v_days FROM public.referral_redemptions rr WHERE rr.referrer_id = v_uid;'),
          reason: 'text pin for the single-fault mutants that are behaviourally equivalent (unqualified relation; SET search_path dropped is caught by A10)');
      expect(
          summaryBody,
          contains("RETURN jsonb_build_object( 'joined', v_joined, 'subscribed', v_subscribed, 'pending', v_pending, 'credited', v_credited, 'days_earned', v_days );"));
      for (final banned in <String>['created_at', 'converted_at,', 'referee_id,', 'razorpay', 'payment']) {
        expect(RegExp('jsonb_build_object\\([^;]*$banned').hasMatch(summaryBody), isFalse, reason: 'the aggregate carries counts and days only: $banned');
      }
    });

    test('referrer_summary ACL: PUBLIC and anon revoked, authenticated granted, in that order', () {
      expect(
          code160,
          contains('REVOKE ALL ON FUNCTION public.referrer_summary() FROM PUBLIC; REVOKE ALL ON FUNCTION public.referrer_summary() FROM anon; '
              'GRANT EXECUTE ON FUNCTION public.referrer_summary() TO authenticated;'));
    });

    test('the promo ceiling: the 1..100 CHECK is REPLACED by 1..90 in ONE ALTER (the old constraint has the same name)', () {
      final alters = RegExp(r'ALTER TABLE [^;]*;').allMatches(code160).map((m) => m.group(0)!).toList();
      expect(alters, <String>[
        'ALTER TABLE public.promo_codes DROP CONSTRAINT IF EXISTS promo_codes_discount_pct_check, '
            'ADD CONSTRAINT promo_codes_discount_pct_check CHECK (discount_pct BETWEEN 1 AND 90);',
      ], reason: 'the ONLY ALTER of 160; a guarded ADD would silently keep the live 1..100 constraint of the same name');
    });

    test('the DDL is bounded by a lock_timeout released at the end; the self-check comes after the grants and before the RESET', () {
      final setIdx = code160.indexOf("SET lock_timeout = '3s';");
      final alter = code160.indexOf('ALTER TABLE ');
      final grant = code160.indexOf('GRANT SELECT (');
      final check = code160.indexOf('DO \$selfcheck\$');
      final reset = code160.indexOf('RESET lock_timeout;');
      expect(setIdx, greaterThanOrEqualTo(0));
      expect(alter, greaterThan(setIdx));
      expect(check, greaterThan(grant));
      expect(code160.indexOf('GRANT EXECUTE ON FUNCTION public.referrer_summary() TO authenticated;'), lessThan(check));
      expect(reset, greaterThan(check));
      final promo = code160.indexOf('ALTER TABLE public.promo_codes');
      expect(promo, greaterThan(check), reason: 'the promo ALTER takes ACCESS EXCLUSIVE on promo_codes to commit, so it runs AFTER everything that can abort the apply');
      expect(promo, lessThan(reset));
    });

    test('the self-check verifies every privilege class and RAISES (aborting the migration)', () {
      final i = code160.indexOf('DO \$selfcheck\$');
      final block = code160.substring(i, code160.indexOf('\$selfcheck\$;', i));
      for (final needle in <String>[
        "ARRAY['anon', 'authenticated']",
        "ARRAY['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER', 'MAINTAIN']",
        "has_table_privilege(v_role, 'public.referral_redemptions', v_priv)",
        "has_any_column_privilege('anon', 'public.referral_redemptions', 'SELECT,INSERT,UPDATE,REFERENCES')",
        "has_any_column_privilege('authenticated', 'public.referral_redemptions', 'INSERT,UPDATE,REFERENCES')",
        "ARRAY['converted_at', 'referrer_reward_days', 'referrer_credited_at', 'referrer_rewarded', 'referee_rewarded']",
        "ARRAY['id', 'code', 'referrer_id', 'referee_id', 'days_granted_each', 'created_at']",
        "has_function_privilege('anon', 'public.referrer_summary()', 'EXECUTE')",
        "NOT has_function_privilege('authenticated', 'public.referrer_summary()', 'EXECUTE')",
        "RAISE EXCEPTION 'migration 160 self-check failed:%', v_bad;",
        // WHOLE statements, not just their operands: a needle that is only an operand survives `IF NOT ...`, `AND false`, or a swapped array
        "IF v_bad <> '' THEN RAISE EXCEPTION 'migration 160 self-check failed:%', v_bad; END IF;",
        "IF has_table_privilege(v_role, 'public.referral_redemptions', v_priv) THEN v_bad := v_bad || format(' %s holds table-level %s;', v_role, v_priv); END IF;",
        "IF has_any_column_privilege('anon', 'public.referral_redemptions', 'SELECT,INSERT,UPDATE,REFERENCES') THEN v_bad := v_bad || ' anon holds a column privilege;'; END IF;",
        "IF has_any_column_privilege('authenticated', 'public.referral_redemptions', 'INSERT,UPDATE,REFERENCES') THEN v_bad := v_bad || ' authenticated holds a column write privilege;'; END IF;",
        "'referee_rewarded'] LOOP IF has_column_privilege('authenticated', 'public.referral_redemptions', v_col, 'SELECT') THEN",
        "'created_at'] LOOP IF NOT has_column_privilege('authenticated', 'public.referral_redemptions', v_col, 'SELECT') THEN",
        "IF has_function_privilege('anon', 'public.referrer_summary()', 'EXECUTE') THEN v_bad := v_bad || ' anon can execute referrer_summary;'; END IF;",
        "IF NOT has_function_privilege('authenticated', 'public.referrer_summary()', 'EXECUTE') THEN v_bad := v_bad || ' authenticated cannot execute referrer_summary;'; END IF;",
        // the two replaced functions keep their ACL (a foreign-grantor EXECUTE survives the owner's REVOKE), and referrer_summary keeps its mode
        "FOREACH v_fn IN ARRAY ARRAY['private.process_referral_conversions()', 'public.redeem_referral_atomic(text, uuid, uuid, integer)'] LOOP FOREACH v_role IN ARRAY ARRAY['anon', 'authenticated'] LOOP IF has_function_privilege(v_role, v_fn::regprocedure, 'EXECUTE') THEN v_bad := v_bad || format(' %s can execute %s;', v_role, v_fn); END IF; END LOOP; END LOOP;",
        "IF NOT EXISTS ( SELECT 1 FROM pg_proc p WHERE p.oid = 'public.referrer_summary()'::regprocedure AND p.prosecdef AND p.provolatile = 's' AND p.proconfig = ARRAY['search_path=public, pg_temp'] ) THEN",
      ]) {
        expect(block, contains(needle));
      }
      expect(block, isNot(contains('aclexplode')),
          reason: 'a PUBLIC EXECUTE entry is already seen by has_function_privilege(anon): a separate aclexplode clause was unreachable dead code');
      expect(block, contains('v_fn text;'), reason: 'the loop variable must be declared');
      expect(block, isNot(contains('service_role')), reason: 'the self-check must never touch the roles the Edge Functions run as');
    });

    test('the inline rollback restores the 159 bodies VERBATIM, in an order that never leaves a caller without its callee', () {
      final lines = sql160.split('\n');
      final start = lines.indexWhere((l) => l.startsWith('-- Rollback (inline;'));
      expect(start, greaterThanOrEqualTo(0));
      final rb = <String>[];
      for (final l in lines.skip(start + 1)) {
        if (l.startsWith('--   ')) {
          final t = l.substring(5);
          if (t.startsWith('-- ')) continue;
          rb.add(t.replaceAll(RegExp(r'\s+$'), ''));
        } else if (l == '--') {
          rb.add('');
        }
      }
      final text = rb.join('\n');
      String fn(String sql, String head) {
        final a = sql.indexOf(head);
        final b = sql.indexOf('\n\$function\$;', a);
        expect(a, greaterThanOrEqualTo(0));
        expect(b, greaterThan(a));
        return sql.substring(a, b + '\n\$function\$;'.length).split('\n').map((l) => l.replaceAll(RegExp(r'\s+$'), '')).join('\n');
      }

      expect(fn(text, 'CREATE OR REPLACE FUNCTION public.redeem_referral_atomic'), fn(sql159, 'CREATE OR REPLACE FUNCTION public.redeem_referral_atomic'));
      expect(fn(text, 'CREATE OR REPLACE FUNCTION private.process_referral_conversions'), fn(sql159, 'CREATE OR REPLACE FUNCTION private.process_referral_conversions'));
      final dropSummary = text.indexOf('DROP FUNCTION IF EXISTS public.referrer_summary();');
      final restoreRedeem = text.indexOf('CREATE OR REPLACE FUNCTION public.redeem_referral_atomic');
      final restoreJob = text.indexOf('CREATE OR REPLACE FUNCTION private.process_referral_conversions');
      final grants = text.indexOf('GRANT SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER, MAINTAIN ON public.referral_redemptions TO anon, authenticated;');   // live relacl arwdDxtm: m = MAINTAIN
      final promo = text.indexOf('ADD  CONSTRAINT promo_codes_discount_pct_check CHECK (discount_pct >= 1 AND discount_pct <= 100);');
      expect(dropSummary, greaterThanOrEqualTo(0));
      expect(restoreRedeem, greaterThan(dropSummary));
      expect(restoreJob, greaterThan(restoreRedeem));
      expect(grants, greaterThan(restoreJob));
      final revokeAll = text.indexOf('REVOKE ALL ON public.referral_redemptions FROM anon, authenticated;');
      expect(revokeAll, greaterThan(restoreJob), reason: 'a table-level GRANT does not remove the six column-level SELECT entries 160 created: REVOKE ALL first');
      expect(grants, greaterThan(revokeAll));
      expect(promo, greaterThan(grants));
    });

    test('no client file that touches referral_redemptions names a payment-status column (they are unreadable to clients)', () {
      final offenders = <String>[];
      for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
        final src = stripDartComments(f.readAsStringSync());
        if (!src.contains('referral_redemptions')) continue;
        for (final h in hidden) {
          if (RegExp('\\b$h\\b').hasMatch(src)) offenders.add('${f.path}: $h');
        }
      }
      expect(offenders, isEmpty,
          reason: 'after migration 160 a client select naming one of these columns (or select *) is refused with 42501; the aggregate is referrer_summary()');
    });

    test('the replica carries the platform default function privileges, the live promo table with the OLD 1..100 CHECK, and the live codes', () {
      final schemaCode = squash(stripSqlComments(File(_replicaSchemaPath).readAsStringSync()));
      final dp = schemaCode.indexOf('ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT EXECUTE ON FUNCTIONS TO anon, authenticated, service_role;');
      expect(dp, greaterThanOrEqualTo(0));
      expect(dp, lessThan(schemaCode.indexOf('CREATE OR REPLACE FUNCTION')), reason: 'the default must be in force BEFORE any function is created');
      expect(schemaCode, contains('CONSTRAINT promo_codes_discount_pct_check CHECK (((discount_pct >= 1) AND (discount_pct <= 100)))'));
      expect(schemaCode, contains("('REPLICA30', 30, current_date + 365), ('REPLICA20', 20, current_date + 365), ('REPLICA15', 15, current_date + 365)"));
      // the replica must keep the LIVE shape that makes an insert without valid_until fail (date NOT NULL, no default) and the live MAINTAIN grant
      expect(schemaCode, contains('valid_until date NOT NULL'));
      expect(schemaCode, contains('GRANT SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER, MAINTAIN ON public.referral_redemptions TO anon, authenticated, service_role;'));
    });

    test('the live verify carries every migration-160 case id exactly once (a deleted or skipped case would otherwise be silent: the SUMMARY is only a count)', () {
      final lv = File('test/sql/referral_pay_on_conversion_live_verify.sql').readAsStringSync();
      for (final id in <String>[
        'Q1a', 'Q1b', 'Q1c', 'Q2', 'Q3', 'Q4', 'Q5a', 'Q5b', 'Q5c', 'Q6a', 'Q6b', 'Q6c', 'Q6d', 'Q6e', 'Q6f', 'Q6g', 'Q6h', 'Q7', 'Q8', 'Q9', 'A10', 'A11',
      ]) {
        expect(RegExp("\\('$id',").allMatches(lv).length, 1, reason: 'case $id must appear exactly once in the live verify');
      }
    });

    test('the live verify supplies every NOT NULL column of the live promo_codes table (valid_until is date NOT NULL with no default) and counts a NULL case as a failure', () {
      final lv = squash(stripSqlComments(File('test/sql/referral_pay_on_conversion_live_verify.sql').readAsStringSync()));
      expect(lv, contains("INSERT INTO public.promo_codes (code, discount_pct, valid_until) VALUES ('ZZVERIFY' || v_col, v_col::int, current_date + 1);"));
      expect(lv, contains('count(*) FILTER (WHERE ok IS NOT TRUE)'), reason: 'a NULL case (an A-case whose subquery returned no row) must be a FAIL, not uncounted');
      expect(lv, contains("IF has_table_privilege('authenticated', 'public.referral_redemptions', 'TRUNCATE') THEN"),
          reason: 'TRUNCATE ignores row security: it is attempted only when the privilege is already gone, so a pre-160 run cannot truncate the live audit table');
    });
  });
}
