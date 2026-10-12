// test/contracts/referral_referrer_cap_migration_test.dart
//
// OI-320 / migration 158 — a referrer earns PRO days for at most 7 CREDITED referrals in any rolling 90 days; the
// referee is always credited. Founder decision 2026-10-11.
//
// WHAT THIS FILE IS, AND IS NOT. These are SOURCE pins on the migration text. They prove the rule is WRITTEN, in the
// definition that is LIVE (the highest-numbered migration defining the function: `CREATE OR REPLACE` makes a
// function's body the last one, CLAUDE.md §4.9). They cannot prove what the function DOES. That is
// test/sql/oi320_referrer_cap_live_verify.sql (28 cases against the real function in one transaction), plus
// test/sql/oi320_referrer_cap_deletion_replica.sql (account deletion) and
// test/sql/oi320_referrer_cap_concurrency_local.sh (two sessions racing for one referrer; a deterministic lock-order
// probe; a statistical mutual-redemption run), the SoT registry's `behavioral_test_path`. They were run against a local
// replica, before and after the migration, and under the SQL mutants of the migration
// (docs/plans/oi320-referrer-cap.md, section 3).
//
// Five layers, each answering a different question:
//   1. THE RULE        the cap (7), the window (90 days, strict `>` on created_at), the per-referrer scope, the
//                      "credited rows only" count, and the decision gating the referrer's credit and ONLY the
//                      referrer's.
//   2. THE ORDER       BOTH users' advisory locks are taken, lowest key first, BEFORE the count and the audit insert:
//                      the count and the insert must not interleave across sessions, and two redemptions that touch a
//                      common user cannot wait on each other's locks.
//   3. WHAT DID NOT    signature, RETURNS void, SECURITY DEFINER, `SET search_path` (a CREATE OR REPLACE that omits
//      CHANGE          it silently undoes migration 053), and the ACL re-assertion. WHAT DID CHANGE: exactly three
//                      ALTER TABLE statements on referral_redemptions (both user columns nullable, both foreign keys
//                      ON DELETE SET NULL in ONE statement), a post-condition block, and a lock_timeout around them,
//                      so deleting an account keeps the audit row: the cap cannot be reopened and a referee cannot
//                      redeem a second code.
//      (3c) the referrer and referee credit statements equal the previous body's, token for token; (3d) the replica
//      schema file is one transaction that refuses a non-empty target and creates its marker last; (3e) the replica
//      carries the live row-level-security shape (RLS on, one SELECT policy, full grants).
//   4. WRITER<->READER the Edge Function calls the RPC with exactly the parameter names the SQL declares, and
//                      passes no cap value: the cap lives in ONE place (the RPC).
//   5. LIVE SCHEMA     the columns the rule reads exist LIVE: `created_at`, `referrer_rewarded`, `referee_rewarded`
//                      (backups/live_schema_columns.json). There is NO `redeemed_at` column; migration 037 names an
//                      index idx_referral_redemptions_redeemed_at (on created_at) and docs/architecture/database.md
//                      listed a column; the first draft of this plan assumed the docs.
//
// Run: flutter test test/contracts/referral_referrer_cap_migration_test.dart

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/migration_cap_reader.dart';

const _fn = 'redeem_referral_atomic';

void main() {
  final latest = latestMigrationDefining(_fn);
  final liveSql = latest?.readAsStringSync() ?? '';
  final block = functionBlock(liveSql, _fn) ?? '';
  // Collapse whitespace so a re-wrapped line cannot hide a pin, and a pin cannot match across a comment.
  String squash(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim();
  final body = squash(block);

  group('the live definition (the highest-numbered migration defining the function)', () {
    test('exists, and is migration 158 or a later one that keeps the cap', () {
      expect(latest, isNotNull);
      expect(migrationNumber(latest!.uri.pathSegments.last), greaterThanOrEqualTo(158),
          reason: 'the cap was introduced by migration 158');
      expect(block, isNotEmpty);
    });
  });

  group('1. the rule', () {
    test('cap is 7 and the window is 90 days, declared as constants', () {
      expect(body, contains('c_referrer_cap CONSTANT integer := 7;'));
      expect(body, contains("c_cap_window CONSTANT interval := interval '90 days';"));
    });

    test('the count is per referrer, over CREDITED rows, in the window (strict >, on created_at)', () {
      final countIdx = body.indexOf('SELECT count(*) INTO v_credited_in_window');
      expect(countIdx, greaterThanOrEqualTo(0));
      final stmt = body.substring(countIdx, body.indexOf(';', countIdx) + 1);
      // The WHOLE statement, not clause-by-clause contains(): an extra predicate (`AND referee_id IS NOT NULL`) or a
      // different aggregate (`count(DISTINCT referee_id)`) would drop the rows of deleted referees from the count and
      // reopen the cap, and every per-clause pin would stay green (round-2 review).
      expect(
          stmt,
          'SELECT count(*) INTO v_credited_in_window FROM referral_redemptions '
          'WHERE referrer_id = p_referrer_id AND referrer_rewarded AND created_at > now() - c_cap_window;');
    });

    test('credited when strictly under the cap', () {
      expect(body, contains('v_credit_referrer := v_credited_in_window < c_referrer_cap;'));
    });

    test('the audit row records both outcomes: referee always true, referrer = the decision', () {
      expect(
          body,
          contains('INSERT INTO referral_redemptions ( code, referrer_id, referee_id, days_granted_each, '
              'referrer_rewarded, referee_rewarded ) VALUES ( p_code, p_referrer_id, p_referee_id, p_days, '
              'v_credit_referrer, true );'));
    });

    test('the decision gates the REFERRER credit and not the referee credit', () {
      final gate = body.indexOf('IF v_credit_referrer THEN');
      final referrerSub = body.indexOf('WHERE user_id = p_referrer_id');
      final refereeSub = body.indexOf('WHERE user_id = p_referee_id');
      expect(gate, greaterThanOrEqualTo(0));
      expect(referrerSub, greaterThan(gate), reason: 'the referrer credit sits inside the IF');
      // The referee block is after the IF closes: nothing between the IF and the referee read re-opens a gate on it.
      final between = body.substring(gate, refereeSub);
      expect('END IF;'.allMatches(between).length, greaterThanOrEqualTo(2),
          reason: 'the outer IF (and the inner insert/extend IF) close before the referee is read');
      // The ENTIRE referee block (the read, the insert branch AND the extend branch) is free of the decision. A
      // 120-character look-back before the first referee WHERE missed `AND v_credit_referrer` on the extend UPDATE.
      final refereeBlock = body.substring(body.indexOf('SELECT MAX(end_date) INTO v_referee_expires'));
      expect(refereeBlock, isNot(contains('v_credit_referrer')),
          reason: 'the referee must be credited, in both branches, whatever the referrer decision was');
      expect('v_credit_referrer'.allMatches(body).length, 4,
          reason: 'declaration, assignment, the audit-row value and the one IF: no other use');
    });
  });

  group('2. the order', () {
    test('both users\' advisory locks are taken, lowest key first, before the count and the audit insert', () {
      const low = 'PERFORM pg_advisory_xact_lock(least(v_key_referrer, v_key_referee));';
      const high = 'PERFORM pg_advisory_xact_lock(greatest(v_key_referrer, v_key_referee));';
      final lowIdx = body.indexOf(low);
      final highIdx = body.indexOf(high);
      final count = body.indexOf('SELECT count(*) INTO v_credited_in_window');
      final insert = body.indexOf('INSERT INTO referral_redemptions');
      expect(lowIdx, greaterThanOrEqualTo(0), reason: 'no lock: two sessions both read 6 and both credit (8)');
      expect(highIdx, greaterThan(lowIdx), reason: 'the higher key second: a fixed order cannot form a lock cycle');
      expect(highIdx, lessThan(count));
      expect(count, lessThan(insert));
      expect('pg_advisory_xact_lock('.allMatches(body).length, 2,
          reason: 'exactly the two sorted locks: a third lock would be a new ordering to prove');
    });

    test('each key is derived from its own user with the same prefix', () {
      expect(
          body,
          contains("v_key_referrer bigint := hashtextextended('redeem_referral_atomic:' || p_referrer_id::text, 0);"));
      expect(
          body,
          contains("v_key_referee bigint := hashtextextended('redeem_referral_atomic:' || p_referee_id::text, 0);"),
          reason: 'a referee key with another prefix would never meet the same user\'s referrer key');
    });

    test('a NULL referrer or referee is refused before anything is locked or written', () {
      const guard = 'IF p_referrer_id IS NULL OR p_referee_id IS NULL THEN RAISE EXCEPTION '
          "'redeem_referral_atomic: referrer and referee are required' USING ERRCODE = '23502'; END IF;";
      final g = body.indexOf(guard);
      expect(g, greaterThanOrEqualTo(0), reason: 'referee_id is nullable now; NULL must not reach the audit insert');
      expect(g, lessThan(body.indexOf('pg_advisory_xact_lock(')));
    });
  });

  group('3. what did not change', () {
    test('signature, return type and security mode', () {
      final code = squash(stripSqlComments(liveSql));
      expect(code, contains('public.redeem_referral_atomic( p_code text, p_referrer_id uuid, p_referee_id uuid, p_days integer )'));
      expect(code, contains('RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO \'public\''),
          reason: 'omitting SET search_path in a CREATE OR REPLACE silently undoes migration 053');
    });

    test('the ACL is re-asserted: service_role only, anon/authenticated/PUBLIC named', () {
      final sql = squash(stripSqlComments(liveSql));
      const sig = 'public.redeem_referral_atomic(text, uuid, uuid, integer)';
      expect(sql, contains('REVOKE EXECUTE ON FUNCTION $sig FROM PUBLIC;'));
      expect(sql, contains('REVOKE EXECUTE ON FUNCTION $sig FROM anon, authenticated;'));
      expect(sql, contains('GRANT EXECUTE ON FUNCTION $sig TO service_role;'));
      expect(RegExp(r'\bGRANT\b').allMatches(sql).length, 1,
          reason: 'service_role only: a second GRANT (anon, authenticated, PUBLIC) would widen the ACL');
    });

    test('the migration header carries the four tags, and says non-destructive', () {
      final head = liveSql.split('\n').take(6).join('\n');
      expect(head, contains('-- Intent:'));
      expect(head, contains('-- Destructive?: no'));
      expect(head, contains('-- Rollback strategy: inline'));
      expect(head, contains('-- Linked diagnose-doc:'));
    });

    test('the only DDL is three ALTER TABLE statements on referral_redemptions; no row rewrite', () {
      final sql = squash(stripSqlComments(liveSql));
      final alters = RegExp(r'ALTER TABLE [^;]*;').allMatches(sql).map((m) => m.group(0)!).toList();
      expect(alters, <String>[
        'ALTER TABLE public.referral_redemptions ALTER COLUMN referrer_id DROP NOT NULL;',
        'ALTER TABLE public.referral_redemptions ALTER COLUMN referee_id DROP NOT NULL;',
        'ALTER TABLE public.referral_redemptions '
            'DROP CONSTRAINT IF EXISTS referral_redemptions_referrer_id_fkey, '
            'DROP CONSTRAINT IF EXISTS referral_redemptions_referee_id_fkey, '
            'ADD CONSTRAINT referral_redemptions_referrer_id_fkey FOREIGN KEY (referrer_id) REFERENCES public.users(id) ON DELETE SET NULL, '
            'ADD CONSTRAINT referral_redemptions_referee_id_fkey FOREIGN KEY (referee_id) REFERENCES public.users(id) ON DELETE SET NULL;',
      ], reason: '`Destructive?: no` holds only while nothing else is altered; the DROP and the ADD are ONE statement');
      final upper = sql.toUpperCase();
      for (final banned in <String>[
        'DROP TABLE', 'DROP COLUMN', 'DROP FUNCTION', 'DROP INDEX', 'TRUNCATE', 'DELETE FROM', 'UPDATE REFERRAL_REDEMPTIONS',
      ]) {
        expect(upper, isNot(contains(banned)), reason: '`Destructive?: no` would be false with: $banned');
      }
      expect(RegExp(r'\bDO \$').allMatches(sql).length, 1, reason: 'exactly one DO block: the post-condition');
    });

    test('the DDL is bounded by a lock_timeout (DROP CONSTRAINT locks public.users) and followed by a post-condition', () {
      final sql = squash(stripSqlComments(liveSql));
      final setIdx = sql.indexOf("SET lock_timeout = '3s';");
      final firstAlter = sql.indexOf('ALTER TABLE ');
      final reset = sql.indexOf('RESET lock_timeout;');
      final grant = sql.indexOf('GRANT EXECUTE ON FUNCTION');
      expect(setIdx, greaterThanOrEqualTo(0));
      expect(firstAlter, greaterThan(setIdx), reason: 'the timeout must precede the first lock-taking statement');
      expect(reset, greaterThan(grant), reason: 'RESET closes the file, after the ACL lines');
      final doIdx = sql.indexOf('DO \$assert_fk\$');
      expect(doIdx, greaterThan(firstAlter));
      final guard = sql.substring(doIdx, sql.indexOf('\$assert_fk\$;', doIdx));
      expect(guard, contains("c.contype = 'f' AND c.confdeltype <> 'n'"));
      expect(guard, contains("a.attname IN ('referrer_id', 'referee_id')"));
      expect(guard, contains("RAISE EXCEPTION 'referral_redemptions still has a foreign key over referrer_id/referee_id that is not ON DELETE SET NULL: %'"));
      expect(guard, contains('is still NOT NULL'));
    });

    test('both columns are made nullable BEFORE the SET NULL foreign keys, and nothing re-creates CASCADE', () {
      final sql = squash(stripSqlComments(liveSql));
      final notNullA = sql.indexOf('ALTER COLUMN referrer_id DROP NOT NULL;');
      final notNullB = sql.indexOf('ALTER COLUMN referee_id DROP NOT NULL;');
      final fk = sql.indexOf('ON DELETE SET NULL');
      final fn = sql.indexOf('CREATE OR REPLACE FUNCTION public.redeem_referral_atomic');
      expect(notNullA, greaterThanOrEqualTo(0));
      expect(notNullB, greaterThanOrEqualTo(0));
      expect(fk, greaterThan(notNullA), reason: 'SET NULL against a NOT NULL column would make every deletion fail');
      expect(fk, greaterThan(notNullB));
      expect(fn, greaterThan(fk));
      expect(RegExp(r'ON DELETE SET NULL[,;]').allMatches(sql).length, 2, reason: 'one per user column (the DO block message also names the phrase)');
      expect(sql, isNot(contains('ON DELETE CASCADE')),
          reason: 'CASCADE on either column is the defect: a deleted account would free a slot or a second redemption');
    });
  });

  group('3b. the inline rollback', () {
    // The rollback block is commented SQL at the end of the migration. It must restore the LIVE definition
    // verbatim (comments included): measured 2026-10-11 on the replica, applying 158 then this block returns
    // md5(pg_get_functiondef) to the live value 1066f4cb5b1c36058fd5c0b635e3209d (length 1825), the CASCADE foreign
    // key and NOT NULL. A rollback that only looked equivalent would have failed that md5.
    List<String> rollbackLines() {
      final lines = liveSql.split('\n');
      final start = lines.indexWhere((l) => l.startsWith('-- Rollback (inline)'));
      expect(start, greaterThanOrEqualTo(0));
      final out = <String>[];
      for (final l in lines.skip(start + 1)) {
        if (l.startsWith('-- -- ')) continue;
        if (l.startsWith('-- ')) {
          out.add(l.substring(3));
        } else if (l == '--') {
          out.add('');
        }
      }
      return out;
    }

    test('the function in the rollback block equals the live definition kept in the replica schema', () {
      final rb = rollbackLines().join('\n');
      final from = rb.indexOf('CREATE OR REPLACE FUNCTION public.redeem_referral_atomic');
      final endMarker = '\n\$function\$;';
      final to = rb.indexOf(endMarker, from);
      expect(from, greaterThanOrEqualTo(0));
      expect(to, greaterThan(from));
      final rollbackFn = rb.substring(from, to + endMarker.length);

      final schema = File('test/sql/oi320_referrer_cap_replica_schema.sql').readAsStringSync();
      final sFrom = schema.indexOf('CREATE OR REPLACE FUNCTION public.redeem_referral_atomic');
      final sTo = schema.indexOf(endMarker, sFrom);
      expect(sFrom, greaterThanOrEqualTo(0));
      expect(sTo, greaterThan(sFrom));
      final liveFn = schema.substring(sFrom, sTo + endMarker.length);
      expect(rollbackFn, liveFn, reason: 'the rollback must restore the live body byte for byte');
    });

    test('the rollback restores both CASCADE keys, deletes the NULL rows first, then SET NOT NULL on both', () {
      final rb = rollbackLines().join('\n');
      final cascadeA = rb.indexOf('FOREIGN KEY (referrer_id) REFERENCES public.users(id) ON DELETE CASCADE');
      final cascadeB = rb.indexOf('FOREIGN KEY (referee_id) REFERENCES public.users(id) ON DELETE CASCADE;');
      final del = rb.indexOf('DELETE FROM public.referral_redemptions WHERE referrer_id IS NULL OR referee_id IS NULL;');
      final notNullA = rb.indexOf('ALTER COLUMN referrer_id SET NOT NULL;');
      final notNullB = rb.indexOf('ALTER COLUMN referee_id SET NOT NULL;');
      expect(cascadeA, greaterThanOrEqualTo(0));
      expect(cascadeB, greaterThanOrEqualTo(0));
      expect(del, greaterThan(cascadeB));
      expect(notNullA, greaterThan(del), reason: 'SET NOT NULL fails while a NULL referrer_id row exists');
      expect(notNullB, greaterThan(del), reason: 'SET NOT NULL fails while a NULL referee_id row exists');
      expect(rb, contains("SET lock_timeout = '3s';"));
      expect(rb, contains('RESET lock_timeout;'));
    });
  });

  group('3c. the credit statements are the previous body\'s, unchanged', () {
    // B-pass of the OI-320 batch (a P3, reproduced with two mutants that every SQL file passed): the referrer credit is
    // re-typed inside the new IF, so dropping `AND status = 'active'` from its MAX(end_date) read, or hard-coding
    // `interval '7 days'` for p_days, changes nothing the behavioural files observe. The cheapest complete pin is
    // equality with the live body kept in the replica schema: the referrer block must equal the old one plus the one
    // closing END IF the new gate adds, and the referee block must equal the old one exactly.
    final schema = File('test/sql/oi320_referrer_cap_replica_schema.sql').readAsStringSync();
    final oldBody = squash(functionBlock(schema, _fn) ?? '');
    const referrerStart = 'SELECT MAX(end_date) INTO v_referrer_expires';
    const refereeStart = 'SELECT MAX(end_date) INTO v_referee_expires';
    String between(String text, String a, String b) {
      final i = text.indexOf(a);
      final j = text.indexOf(b, i);
      expect(i, greaterThanOrEqualTo(0), reason: 'anchor missing: $a');
      expect(j, greaterThan(i), reason: 'anchor missing after $a: $b');
      return text.substring(i, j);
    }

    test('the referrer credit equals the previous body\'s, inside exactly one extra END IF', () {
      expect(oldBody, isNotEmpty);
      final oldReferrer = between(oldBody, referrerStart, refereeStart);
      final newReferrer = between(body, referrerStart, refereeStart);
      expect(newReferrer, '${oldReferrer}END IF; ',
          reason: 'the credit logic is unchanged; only the gate around it is new');
    });

    test('the referee credit equals the previous body\'s, exactly', () {
      expect(body.substring(body.indexOf(refereeStart)), oldBody.substring(oldBody.indexOf(refereeStart)));
    });
  });

  group('3d. the replica schema file is one transaction, refuses a non-empty target, marker last', () {
    // B-pass of the OI-320 batch (a P2, reproduced): run in psql's default mode against a database that already held the
    // replica, the failing CREATE TABLEs were skipped, the later statements still ran, the capped function was replaced by
    // the old body, 20 users were added and a valid marker was left, so the delete-capable replica-only files then ran.
    final code = squash(stripSqlComments(File('test/sql/oi320_referrer_cap_replica_schema.sql').readAsStringSync()));

    test('BEGIN first, COMMIT last, exactly one of each', () {
      expect(code.startsWith('BEGIN; '), isTrue);
      expect(code.endsWith(' COMMIT;'), isTrue);
      expect('BEGIN;'.allMatches(code).length, 1);
      expect('COMMIT;'.allMatches(code).length, 1);
    });

    test('a guard refuses a target that already holds any of the replica objects', () {
      final g = code.indexOf('DO \$guard\$');
      expect(g, greaterThanOrEqualTo(0));
      expect(g, lessThan(code.indexOf('CREATE TABLE public.users')), reason: 'the guard runs before anything is created');
      final guard = code.substring(g, code.indexOf('\$guard\$;', g));
      for (final probe in <String>[
        "to_regclass('public.users')",
        "to_regclass('public.referral_redemptions')",
        "to_regclass('public.subscriptions')",
        "to_regclass('public.oi320_replica_marker')",
        "to_regprocedure('public.redeem_referral_atomic(text,uuid,uuid,integer)')",
        "to_regnamespace('auth')",
      ]) {
        expect(guard, contains('$probe IS NOT NULL'), reason: 'the guard must probe $probe');
      }
      expect(guard, contains("RAISE EXCEPTION 'REFUSED"));
    });

    test('the marker is created LAST, after every other object and the fixture users', () {
      final marker = code.indexOf('CREATE TABLE public.oi320_replica_marker');
      expect(marker, greaterThanOrEqualTo(0));
      expect(marker, greaterThan(code.indexOf('INSERT INTO public.users')));
      expect(marker, greaterThan(code.indexOf('GRANT EXECUTE ON FUNCTION public.redeem_referral_atomic')));
      expect('CREATE TABLE public.'.allMatches(code.substring(marker + 1)).length, 0, reason: 'nothing is created after the marker');
    });
  });

  group('3e. the replica carries the live row-level-security shape', () {
    // Hermes pass of the OI-320 batch (a P2): the replica ran with RLS OFF, so no file observed who can read or WRITE the
    // audit rows. The cap holds only while an authenticated user cannot rewrite or delete their own rows; live (read
    // 2026-10-11) that is RLS on + ONE select policy and no write policy, with full table grants to anon/authenticated.
    // The behaviour is test/sql/oi320_referrer_cap_deletion_replica.sql K6 and live verify I7; these pins keep the replica
    // that those cases run against from drifting back to RLS off or to a second policy.
    final code = squash(stripSqlComments(File('test/sql/oi320_referrer_cap_replica_schema.sql').readAsStringSync()));

    test('RLS is enabled on the table, with exactly one policy, a SELECT policy over both user columns', () {
      expect(code, contains('ALTER TABLE public.referral_redemptions ENABLE ROW LEVEL SECURITY;'));
      expect('CREATE POLICY'.allMatches(code).length, 1, reason: 'live has exactly one policy; a write policy would hide the very hole K6 tests');
      expect(
          code,
          contains('CREATE POLICY "Users can read own redemptions" ON public.referral_redemptions FOR SELECT '
              'USING (((select auth.uid()) = referrer_id) OR ((select auth.uid()) = referee_id));'));
    });

    test('anon and authenticated hold the live full table grants (so RLS is the only barrier)', () {
      expect(
          code,
          contains('GRANT SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER ON public.referral_redemptions '
              'TO anon, authenticated, service_role;'));
    });
  });

  group('4. writer<->reader: the Edge Function and the RPC agree', () {
    test('the EF calls the RPC with exactly the declared parameter names and passes no cap value', () {
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
      // Hermes pass: the Dart scan above cannot see TypeScript. A property read (`row.referee_id`) or a subscript
      // (`row["referrer_id"]`) in an Edge Function would treat a deleted party's NULL as a string.
      final hits = <String>[];
      final prop = RegExp(r'\b[A-Za-z_][A-Za-z0-9_]*\??\.(referee_id|referrer_id)\b');
      final sub = RegExp(r"""\[\s*['"`](referee_id|referrer_id)['"`]\s*\]""");
      final dir = Directory('supabase/functions');
      for (final f in dir.listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.ts'))) {
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

  group('5. live schema', () {
    test('the columns the rule reads exist live, and `redeemed_at` does not', () {
      final snap = jsonDecode(File('backups/live_schema_columns.json').readAsStringSync()) as Map<String, dynamic>;
      Map<String, dynamic> tables = snap;
      if (snap['tables'] is Map<String, dynamic>) tables = snap['tables'] as Map<String, dynamic>;
      final cols = (tables['referral_redemptions'] as List).cast<String>();
      expect(cols, containsAll(<String>['created_at', 'referrer_rewarded', 'referee_rewarded', 'referrer_id']));
      expect(cols, isNot(contains('redeemed_at')),
          reason: 'migration 037 names an index idx_..._redeemed_at and database.md listed a column; the live table has only created_at');
      expect(stripSqlComments(liveSql), isNot(contains('redeemed_at')),
          reason: 'the executable SQL must read the column that exists');
    });
  });
}
